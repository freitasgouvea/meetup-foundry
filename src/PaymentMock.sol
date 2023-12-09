/// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Vault} from "./Vault.sol";
import {CCIPAdapter} from "./CCIPAdapter.sol";

contract PaymentMock is Ownable, Pausable, ReentrancyGuard {
    Vault public vault;
    CCIPAdapter public adapter;

    /// Fuji testnet chain selector
    uint64 public constant CURRENT_CHAIN = 14767482510784806043;

    constructor (address _vaultAddress, address _adapter) Ownable(msg.sender) {
        vault = Vault(_vaultAddress);
        adapter = CCIPAdapter(_adapter);
    }

    function simulatePay(
        address _token, 
        address _to, 
        uint256 _amount, 
        uint64 _destinationChainSelector
    ) public whenNotPaused nonReentrant {
        require(_token != address(0), "PaymentMock: token address cannot be zero");
        require(_to != address(0), "PaymentMock: _to address cannot be zero");
        require(_amount > 0, "PaymentMock: _amount must be greater than zero");
        require(IERC20(_token).balanceOf(address(vault)) >= _amount, "PaymentMock: vault balance must be greater than or equal to _amount");
        require(adapter.allowlistedChains(_destinationChainSelector), "PaymentMock: destination chain is not allowlisted");

        if (_destinationChainSelector == CURRENT_CHAIN) {
            vault.pay(_token, _amount, _to);
            return;
        }

        vault.pay(_token,_amount, address(this));
        IERC20(_token).approve(address(adapter), _amount);
        CCIPAdapter(address(adapter)).send(_token, _amount, _to, _destinationChainSelector);
    }
}