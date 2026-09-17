// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPerplExchange} from "./interfaces/IPerplExchange.sol";
import {FundingReader} from "./lib/FundingReader.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title PremiaSwap — funding swaps on Perpl
/// @notice Fixes the funding cost of a Perpl perp position in advance.
///
/// One side pays a constant `k` per lot per funding interval. The other pays
/// whatever funding actually accrued. The realised leg is read straight out of
/// Perpl's own accumulator via `getFundingSumAtBlock`, so a hedger holding L
/// lots on Perpl and L lots here has *zero* basis: the number that settles this
/// swap is the identical number that charged their perp.
///
/// Design constraints, deliberate:
///  - Fully collateralised. Both sides escrow `capPerLot` per lot and the net
///    payoff is clamped to +/- that. The pot is solvent by construction: every
///    matched pair escrows 2*cap and pays out exactly 2*cap. No margin engine,
///    no liquidation keeper, no ADL, no bad debt, ever.
///  - No oracle and no keeper. Settlement is a view call on Perpl, callable by
///    anyone, at any time after expiry.
///  - Capital-inefficient versus a margined swap. That is the trade accepted
///    to remove an entire class of failure. Margin sized off Perpl's own
///    funding clamp is the roadmap, not this version.
contract PremiaSwap {
    using FundingReader for IPerplExchange;

    /// PayFixed pays `k` each interval and receives realised funding.
    /// ReceiveFixed is the mirror.
    enum Side { PayFixed, ReceiveFixed }

    struct Series {
        uint16  marketId;
        uint64  startBlock;      // accrual begins; trading closes here
        uint64  endBlock;        // accrual ends
        int128  minK;            // price of tick 0, funding units per lot per interval
        uint64  tickStep;        // funding units between adjacent ticks
        uint128 capPerLot;       // escrow and payoff bound per lot, funding units
        uint128 unitScale;       // collateral wei per 1 funding unit
        bool    settled;
        int128  netPerLot;       // realised minus nothing; the raw float leg
        uint32  intervals;       // funding events actually spanned
    }

    struct Quote {
        address maker;
        uint128 lots;
        bool    live;
    }

    struct Fill {
        uint128 lots;
        int128  k;
        Side    side;
    }

    IPerplExchange public immutable perpl;
    IERC20 public immutable collateral;

    Series[] private _series;

    // seriesId => side => tick => FIFO queue
    mapping(uint256 => mapping(uint8 => mapping(uint8 => Quote[]))) private _book;
    mapping(uint256 => mapping(uint8 => mapping(uint8 => uint256))) private _head;
    // seriesId => side => 256-tick occupancy bitmap
    mapping(uint256 => mapping(uint8 => uint256)) private _bitmap;

    mapping(uint256 => mapping(address => Fill[])) private _fills;
    mapping(uint256 => mapping(address => bool)) public claimed;

    uint256 private _lock = 1;

    event SeriesCreated(uint256 indexed id, uint16 marketId, uint64 startBlock, uint64 endBlock);
    event Quoted(uint256 indexed id, address indexed maker, Side side, uint8 tick, uint128 lots);
    event Cancelled(uint256 indexed id, address indexed maker, Side side, uint8 tick, uint128 lots);
    event Filled(uint256 indexed id, address indexed taker, address indexed maker, Side takerSide, uint8 tick, uint128 lots);
    event Settled(uint256 indexed id, int128 netPerLot, uint32 intervals);
    event Claimed(uint256 indexed id, address indexed account, uint256 payout);

    error TradingClosed();
    error NotExpired();
    error AlreadySettled();
    error NotSettled();
    error AlreadyClaimed();
    error BadSeries();
    error NoLiquidity();
    error LimitCrossed();
    error Unfilled(uint128 remaining);
    error ZeroLots();
    error TransferFailed();
    error Reentrancy();
    error PerLotOverflow(int256 perLot);
    error NegativePayout(int256 total);

    modifier lock() {
        if (_lock != 1) revert Reentrancy();
        _lock = 2;
        _;
        _lock = 1;
    }

    constructor(IPerplExchange _perpl, IERC20 _collateral) {
        perpl = _perpl;
        collateral = _collateral;
    }

    // ---------------------------------------------------------------- series

    /// @notice Anyone may list a series. There is no admin, no pause, no owner.
    function createSeries(
        uint16 marketId,
        uint64 startBlock,
        uint64 endBlock,
        int128 minK,
        uint64 tickStep,
        uint128 capPerLot,
        uint128 unitScale
    ) external returns (uint256 id) {
        if (startBlock <= block.number || endBlock <= startBlock) revert BadSeries();
        if (tickStep == 0 || capPerLot == 0 || unitScale == 0) revert BadSeries();

        _series.push(Series({
            marketId: marketId,
            startBlock: startBlock,
            endBlock: endBlock,
            minK: minK,
            tickStep: tickStep,
            capPerLot: capPerLot,
            unitScale: unitScale,
            settled: false,
            netPerLot: 0,
            intervals: 0
        }));
        id = _series.length - 1;
        emit SeriesCreated(id, marketId, startBlock, endBlock);
    }

    function seriesCount() external view returns (uint256) { return _series.length; }
    function getSeries(uint256 id) external view returns (Series memory) { return _series[id]; }
    function priceOf(uint256 id, uint8 tick) public view returns (int128) {
        Series storage s = _series[id];
        return s.minK + int128(uint128(s.tickStep)) * int128(uint128(tick));
    }

    // ------------------------------------------------------------------ book

    /// @notice Post a resting quote. Escrows the full downside immediately.
    function postQuote(uint256 id, Side side, uint8 tick, uint128 lots) external lock {
        Series storage s = _series[id];
        if (block.number >= s.startBlock) revert TradingClosed();
        if (lots == 0) revert ZeroLots();

        _pull(msg.sender, _escrow(s, lots));

        _book[id][uint8(side)][tick].push(Quote({maker: msg.sender, lots: lots, live: true}));
        _bitmap[id][uint8(side)] |= (uint256(1) << tick);

        emit Quoted(id, msg.sender, side, tick, lots);
    }

    /// @notice Withdraw a resting quote and its escrow.
    function cancelQuote(uint256 id, Side side, uint8 tick, uint256 index) external lock {
        Series storage s = _series[id];
        if (block.number >= s.startBlock) revert TradingClosed();

        Quote storage q = _book[id][uint8(side)][tick][index];
        require(q.maker == msg.sender && q.live, "not yours or not live");

        uint128 lots = q.lots;
        q.live = false;
        q.lots = 0;
        _sweepTick(id, uint8(side), tick);

        _push(msg.sender, _escrow(s, lots));
        emit Cancelled(id, msg.sender, side, tick, lots);
    }

    /// @notice Cross the book. `limitTick` bounds the worst price accepted.
    /// A PayFixed taker lifts the lowest ReceiveFixed quote, so its limit is a
    /// ceiling; a ReceiveFixed taker hits the highest PayFixed quote, so its
    /// limit is a floor. Price priority is enforced by the bitmap, time
    /// priority by the per-tick FIFO — no off-chain matching engine.
    function take(uint256 id, Side side, uint128 lots, uint8 limitTick) external lock {
        Series storage s = _series[id];
        if (block.number >= s.startBlock) revert TradingClosed();
        if (lots == 0) revert ZeroLots();

        uint8 makerSide = uint8(side == Side.PayFixed ? Side.ReceiveFixed : Side.PayFixed);
        bool takerBuysFixed = side == Side.PayFixed; // walks ticks upward

        _pull(msg.sender, _escrow(s, lots));

        uint128 remaining = lots;
        while (remaining > 0) {
            uint256 bm = _bitmap[id][makerSide];
            if (bm == 0) break;

            uint8 tick = takerBuysFixed ? _lowestBit(bm) : _highestBit(bm);
            if (takerBuysFixed ? tick > limitTick : tick < limitTick) break;

            remaining = _consumeTick(id, makerSide, tick, side, remaining);
        }

        if (remaining == lots) revert NoLiquidity();
        if (remaining > 0) {
            // partial fill: hand back the escrow for lots that never traded
            _push(msg.sender, _escrow(s, remaining));
        }
    }

    function _consumeTick(
        uint256 id,
        uint8 makerSide,
        uint8 tick,
        Side takerSide,
        uint128 remaining
    ) private returns (uint128) {
        Quote[] storage queue = _book[id][makerSide][tick];
        uint256 h = _head[id][makerSide][tick];
        int128 k = priceOf(id, tick);

        while (h < queue.length && remaining > 0) {
            Quote storage q = queue[h];
            if (!q.live || q.lots == 0) { unchecked { ++h; } continue; }

            uint128 traded = q.lots < remaining ? q.lots : remaining;
            q.lots -= traded;
            unchecked { remaining -= traded; }

            _fills[id][q.maker].push(Fill({lots: traded, k: k, side: Side(makerSide)}));
            _fills[id][msg.sender].push(Fill({lots: traded, k: k, side: takerSide}));
            emit Filled(id, msg.sender, q.maker, takerSide, tick, traded);

            if (q.lots == 0) { q.live = false; unchecked { ++h; } }
        }

        _head[id][makerSide][tick] = h;
        _sweepTick(id, makerSide, tick);
        return remaining;
    }

    /// @dev Clears the tick bit once nothing live remains behind the head.
    function _sweepTick(uint256 id, uint8 side, uint8 tick) private {
        Quote[] storage queue = _book[id][side][tick];
        uint256 h = _head[id][side][tick];
        for (uint256 i = h; i < queue.length; ++i) {
            if (queue[i].live && queue[i].lots > 0) return;
        }
        _bitmap[id][side] &= ~(uint256(1) << tick);
    }

    // ------------------------------------------------------------ settlement

    /// @notice Read the realised funding for the window and freeze it.
    /// Permissionless, and correct whenever it is called: both endpoints are
    /// historical lookups inside Perpl, so a late call reads the same numbers
    /// an on-time one would. The interval count comes from the funding-event
    /// blocks Perpl actually recorded, so the fixed leg cannot desync.
    function settle(uint256 id) external {
        Series storage s = _series[id];
        if (s.settled) revert AlreadySettled();
        if (block.number <= s.endBlock) revert NotExpired();

        (int256 perLot, uint256 intervals) =
            perpl.accrual(s.marketId, s.startBlock, s.endBlock);

        // Truncating either of these would misprice settlement silently, so
        // both are checked rather than assumed small.
        if (perLot > type(int128).max || perLot < type(int128).min) {
            revert PerLotOverflow(perLot);
        }
        if (intervals > type(uint32).max) revert PerLotOverflow(int256(intervals));
        s.netPerLot = int128(perLot);
        s.intervals = uint32(intervals);
        s.settled = true;
        emit Settled(id, s.netPerLot, s.intervals);
    }

    /// @notice Net payout for every fill the caller holds in this series.
    function claim(uint256 id) external lock {
        Series storage s = _series[id];
        if (!s.settled) revert NotSettled();
        if (claimed[id][msg.sender]) revert AlreadyClaimed();
        claimed[id][msg.sender] = true;

        Fill[] storage f = _fills[id][msg.sender];
        int256 cap = int256(uint256(s.capPerLot));
        int256 total;

        for (uint256 i = 0; i < f.length; ++i) {
            int256 net = int256(s.netPerLot) - int256(f[i].k) * int256(uint256(s.intervals));
            if (net > cap) net = cap;
            if (net < -cap) net = -cap;
            int256 perLot = f[i].side == Side.PayFixed ? cap + net : cap - net;
            total += perLot * int256(uint256(f[i].lots));
        }

        // Every term is (cap + net) or (cap - net) with net clamped to +/-cap,
        // so each lies in [0, 2*cap] and the sum cannot go negative. Asserted
        // rather than argued, because an unchecked cast here would wrap.
        if (total < 0) revert NegativePayout(total);
        uint256 payout = uint256(total) * s.unitScale;
        if (payout > 0) _push(msg.sender, payout);
        emit Claimed(id, msg.sender, payout);
    }

    function fillsOf(uint256 id, address account) external view returns (Fill[] memory) {
        return _fills[id][account];
    }

    /// @notice What `claim` would pay right now. For the UI's position panel.
    function quoteClaim(uint256 id, address account) external view returns (uint256) {
        Series storage s = _series[id];
        if (!s.settled || claimed[id][account]) return 0;
        Fill[] storage f = _fills[id][account];
        int256 cap = int256(uint256(s.capPerLot));
        int256 total;
        for (uint256 i = 0; i < f.length; ++i) {
            int256 net = int256(s.netPerLot) - int256(f[i].k) * int256(uint256(s.intervals));
            if (net > cap) net = cap;
            if (net < -cap) net = -cap;
            total += (f[i].side == Side.PayFixed ? cap + net : cap - net)
                   * int256(uint256(f[i].lots));
        }
        if (total < 0) return 0;
        return uint256(total) * s.unitScale;
    }

    // ---------------------------------------------------------------- views

    function bestTick(uint256 id, Side side) external view returns (bool ok, uint8 tick) {
        uint256 bm = _bitmap[id][uint8(side)];
        if (bm == 0) return (false, 0);
        return (true, side == Side.ReceiveFixed ? _lowestBit(bm) : _highestBit(bm));
    }

    function bitmap(uint256 id, Side side) external view returns (uint256) {
        return _bitmap[id][uint8(side)];
    }

    function depthAt(uint256 id, Side side, uint8 tick) external view returns (uint128 lots) {
        Quote[] storage queue = _book[id][uint8(side)][tick];
        for (uint256 i = _head[id][uint8(side)][tick]; i < queue.length; ++i) {
            if (queue[i].live) lots += queue[i].lots;
        }
    }

    // -------------------------------------------------------------- internal

    function _escrow(Series storage s, uint128 lots) private view returns (uint256) {
        return uint256(s.capPerLot) * uint256(lots) * uint256(s.unitScale);
    }

    function _pull(address from, uint256 amount) private {
        if (!collateral.transferFrom(from, address(this), amount)) revert TransferFailed();
    }

    function _push(address to, uint256 amount) private {
        if (!collateral.transfer(to, amount)) revert TransferFailed();
    }

    function _lowestBit(uint256 x) private pure returns (uint8) {
        uint256 isolated = x & (~x + 1);
        return _log2(isolated);
    }

    function _highestBit(uint256 x) private pure returns (uint8) {
        return _log2(x);
    }

    function _log2(uint256 x) private pure returns (uint8 r) {
        if (x >> 128 > 0) { x >>= 128; r += 128; }
        if (x >> 64  > 0) { x >>= 64;  r += 64;  }
        if (x >> 32  > 0) { x >>= 32;  r += 32;  }
        if (x >> 16  > 0) { x >>= 16;  r += 16;  }
        if (x >> 8   > 0) { x >>= 8;   r += 8;   }
        if (x >> 4   > 0) { x >>= 4;   r += 4;   }
        if (x >> 2   > 0) { x >>= 2;   r += 2;   }
        if (x >> 1   > 0) {            r += 1;   }
    }
}
