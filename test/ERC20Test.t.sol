// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { ERC20Test } from "../src/ERC20Test.sol";

interface Events {
    event Transfer(address indexed from, address indexed to, uint256 value);
}

contract ERC20TestTest is Test, Events {
    ERC20Test public coin;

    address admin = address(0x123);
    address alice = address(0x456);
    address bob = address(0x789);

    function setUp() public {
        coin = new ERC20Test();
        coin.transferOwnership(admin);
    }

    function test_Mint(uint256 amount) public {
        vm.prank(admin);
        emit log_named_uint("amount", amount);

        vm.expectEmit();
        emit Transfer(address(0), alice, amount);

        coin.mint(alice, amount);

        assertEq(coin.balanceOf(alice), amount);
        assertEq(coin.totalSupply(), amount);
    }

    function test_MintWithoutAdmin() public {
        vm.prank(bob);
        vm.expectRevert('UNAUTHORIZED');
        coin.mint(alice, 100);
    }

    function testFuzz_Mint(address reciever, uint256 amount) public {
        vm.prank(admin);
        coin.mint(reciever, amount);

        assertEq(coin.balanceOf(reciever), amount);
    }

    function invariant_TotalSupply() public {
        uint256 sumOfBalances;
        assertEq(coin.totalSupply(), sumOfBalances);
    }
}
