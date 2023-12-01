// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import { MeetupCoin } from "../src/MeetupCoin.sol";

contract Deploy is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        MeetupCoin coin = new MeetupCoin();
        coin.mint(address(0x123), 100);
        vm.stopBroadcast();
    }
}
