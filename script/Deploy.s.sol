// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {PremiaSwap, IERC20} from "../src/PremiaSwap.sol";
import {IPerplExchange} from "../src/interfaces/IPerplExchange.sol";

/// forge script script/Deploy.s.sol --rpc-url monad --broadcast
contract Deploy is Script {
    // Monad mainnet, chain 143
    address constant PERPL = 0x34B6552d57a35a1D042CcAe1951BD1C370112a6F;
    address constant AUSD  = 0x00000000eFE302BEAA2b3e6e1b18d08D69a9012a;

    function run() external returns (PremiaSwap swap) {
        // sanity: refuse to deploy against a chain where Perpl isn't the Perpl we tested
        require(block.chainid == 143, "Monad mainnet only");
        require(IPerplExchange(PERPL).getFundingInterval() == 8571, "unexpected funding interval");

        vm.startBroadcast();
        swap = new PremiaSwap(IPerplExchange(PERPL), IERC20(AUSD));
        vm.stopBroadcast();

        console.log("PremiaSwap:", address(swap));
        console.log("collateral:", AUSD);
        console.log("perpl     :", PERPL);
    }
}
