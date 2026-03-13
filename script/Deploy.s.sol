// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {TokenVesting} from "../src/TokenVesting.sol";

contract DeployTokenVesting is Script {
    function run() external {
        address token = vm.envAddress("VESTING_TOKEN");

        vm.startBroadcast();
        TokenVesting vesting = new TokenVesting(token);
        console.log("TokenVesting deployed:", address(vesting));
        console.log("Token:", token);
        console.log("Owner:", vesting.owner());
        vm.stopBroadcast();
    }
}
