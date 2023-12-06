// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { ERC20Test } from "../src/ERC20Test.sol";
import { Vault } from "../src/Vault.sol";

interface Events {
    event Transfer(address indexed from, address indexed to, uint256 value);
}

contract VaultTest is Test, Events {
    ERC20Test public coin;
    Vault public vault;

    address owner = address(0x123);
    address paymentContractAddress = address(0x999);
    address alice = address(0x456);
    address bob = address(0x789);

    function setUp() public {
        vm.startPrank(owner);
        coin = new ERC20Test();
        vault = new Vault();
        vault.initialize(address(coin), paymentContractAddress);
        vm.stopPrank();
    }

    function test_Deposit(uint256 amount) public {
        if(amount == 0) {
            amount = 100;
        }

        vm.prank(owner);
        coin.mint(alice, amount);

        vm.prank(alice);
        coin.approve(address(vault), amount);

        vm.expectEmit();
        emit Transfer(alice, address(vault), amount);

        vm.prank(alice);
        vault.deposit(amount);

        assertEq(coin.balanceOf(address(vault)), amount);
        assertEq(vault.vaultBalance(), amount);
    }

    function test_Pay (uint256 amount) public {
        if(amount == 0) {
          amount = 100;
        }  
        
        test_Deposit(amount);

        vm.expectEmit();
        emit Transfer(address(vault), bob, amount);

        vm.prank(paymentContractAddress);
        vault.pay(amount, bob);


        assertEq(coin.balanceOf(address(vault)), 0);
        assertEq(coin.balanceOf(bob), amount);
        assertEq(vault.vaultBalance(), 0);
    }

    function test_Withdraw (uint256 amount) public {
        if(amount == 0) {
          amount = 100;
        }  
        
        test_Deposit(amount);

        vm.expectEmit();
        emit Transfer(address(vault), owner, amount);

        vm.prank(owner);
        vault.withdraw(amount);

        assertEq(coin.balanceOf(address(vault)), 0);
        assertEq(coin.balanceOf(owner), amount);
        assertEq(vault.vaultBalance(), 0);
    }
}
