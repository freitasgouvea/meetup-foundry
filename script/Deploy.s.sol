// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import { ERC20Test } from "../src/ERC20Test.sol";

contract Deploy is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        ERC20Test coin = new ERC20Test();
        coin.mint(address(0x123), 100);
        vm.stopBroadcast();
    }
}
