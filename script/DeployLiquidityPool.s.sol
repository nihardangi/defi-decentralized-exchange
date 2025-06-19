// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {LiquidityPool} from "../src/LiquidityPool.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployLiquidityPool is Script {
    function run() external {
        deploy();
    }

    function deploy() public returns (LiquidityPool, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address token, address account) = helperConfig.activeNetworkConfig();

        vm.startBroadcast(account);
        LiquidityPool lp = new LiquidityPool(token);
        vm.stopBroadcast();
        return (lp, helperConfig);
    }
}
