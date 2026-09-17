// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {PremiaSwap} from "../src/PremiaSwap.sol";
import {IPerplExchange} from "../src/interfaces/IPerplExchange.sol";

/// Creates one series. REFUSES to run until the unit scale for this market has
/// been verified against a real Perpl position by script/verify_units.py.
///
///   MARKET=50 START_IN=200 INTERVALS=33 CAP=500 TICK_STEP=1 MIN_K=0 \
///   SWAP=0x... forge script script/CreateSeries.s.sol --rpc-url monad --broadcast
contract CreateSeries is Script {
    error UnitScaleUnverified(uint256 marketId);
    error UnitScaleMismatch(uint256 fromEvidence, uint256 fromEnv);

    function run() external {
        uint256 marketId  = vm.envUint("MARKET");
        uint256 startIn   = vm.envOr("START_IN", uint256(200));   // blocks from now
        uint256 intervals = vm.envOr("INTERVALS", uint256(33));   // ~24h
        uint128 cap       = uint128(vm.envUint("CAP"));
        uint64  tickStep  = uint64(vm.envUint("TICK_STEP"));
        int128  minK      = int128(vm.envInt("MIN_K"));
        PremiaSwap swap   = PremiaSwap(vm.envAddress("SWAP"));

        uint128 unitScale = _verifiedUnitScale(marketId);

        uint64 startBlock = uint64(block.number + startIn);
        uint64 endBlock   = uint64(startBlock + intervals * 8571);

        vm.startBroadcast();
        uint256 id = swap.createSeries(
            uint16(marketId), startBlock, endBlock, minK, tickStep, cap, unitScale
        );
        vm.stopBroadcast();

        console.log("series    :", id);
        console.log("market    :", marketId);
        console.log("unitScale :", unitScale);
        console.log("start blk :", startBlock);
        console.log("end blk   :", endBlock);
    }

    /// The gate. evidence/unit-scale-<market>.json is written only by
    /// verify_units.py, and only when Perpl's own position accounting agrees
    /// with (fsumDelta * lots * scale). No file, no series.
    function _verifiedUnitScale(uint256 marketId) internal view returns (uint128) {
        string memory path = string.concat(
            "evidence/unit-scale-", vm.toString(marketId), ".json"
        );
        if (!vm.exists(path)) revert UnitScaleUnverified(marketId);

        string memory json = vm.readFile(path);
        uint256 fromEvidence = vm.parseJsonUint(json, ".unitScale");
        require(vm.parseJsonBool(json, ".verified"), "evidence says not verified");

        uint256 fromEnv = vm.envOr("UNIT_SCALE", fromEvidence);
        if (fromEnv != fromEvidence) revert UnitScaleMismatch(fromEvidence, fromEnv);

        return uint128(fromEvidence);
    }
}
