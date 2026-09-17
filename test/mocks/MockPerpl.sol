// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// Mirrors the mainnet behaviour verified in FundingReader.fork.t.sol:
/// funding sums are recorded on an 8571-block grid and a lookup snaps DOWN to
/// the last event at or before the requested block.
contract MockPerpl {
    uint256 public constant INTERVAL = 8571;

    mapping(uint256 => mapping(uint256 => int256)) private _sum; // market => feb => sum
    mapping(uint256 => uint256[]) private _events;

    function setFundingSum(uint256 marketId, uint256 feb, int256 sum) external {
        require(feb % INTERVAL == 0, "off grid");
        _sum[marketId][feb] = sum;
        _events[marketId].push(feb);
    }

    function getFundingInterval() external pure returns (uint256) { return INTERVAL; }

    function getFundingSumAtBlock(uint256 marketId, uint256 blockNumber)
        external view returns (int256 sum, uint256 atBlock)
    {
        uint256[] storage e = _events[marketId];
        for (uint256 i = 0; i < e.length; ++i) {
            if (e[i] <= blockNumber && e[i] > atBlock) atBlock = e[i];
        }
        if (atBlock == 0) return (0, 0);
        return (_sum[marketId][atBlock], atBlock);
    }

    function getAccountByAddr(address) external pure returns (uint256) { return 0; }
}
