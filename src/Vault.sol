/// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/**
* @title Vault contract
* @notice This contract holds the coins deposited by the users
* @notice The payment contract can withdraw coins from the vault
*/
contract Vault is Ownable, Pausable, ReentrancyGuard {

  ERC20 public coin;
  address public paymentContractAddress;
  bool public initialized;
  uint256 public vaultBalance;

  event Deposit(address indexed from, uint256 amount);
  event Pay(address indexed to, uint256 amount);
  event Withdraw(address indexed to, uint256 amount);

  /**
  * @notice Create a new vault
  * @dev The vault is paused by default
  * @dev The owner of the vault is the deployer
  */
  constructor() Ownable(msg.sender) {
    _pause();
  }

  /**
  * @notice Initialize the vault
  * @dev This function can only be called once
  * @param _coinAddress The address of the coin contract
  * @param _payerContractAddress The address of the payer contract
  */
  function initialize(address _coinAddress, address _payerContractAddress) public onlyOwner {
    require(!initialized, "Vault: already initialized");
    require(_coinAddress != address(0), "Vault: coin address cannot be zero");
    require(_payerContractAddress != address(0), "Vault: payer contract address cannot be zero");

    coin = ERC20(_coinAddress);
    paymentContractAddress = _payerContractAddress;
    vaultBalance = 0;
    _unpause();
    initialized = true;
  }

  /**
  * @notice Deposit coins into the vault
  * @dev This function can only be called when the vault is not paused
  * @param _amount The amount of coins to deposit
  */
  function deposit(uint256 _amount) public whenNotPaused nonReentrant {
    require(_amount > 0, "Vault: _amount must be greater than zero");
    require (coin.allowance(msg.sender, address(this)) >= _amount, "Vault: allowance must be greater than or equal to _amount");

    vaultBalance += _amount;
    coin.transferFrom(msg.sender, address(this), _amount);

    emit Deposit(msg.sender, _amount);
  }

  /**
  * @notice Pay coins from the vault
  * @dev This function can only be called by the payment contract
  * @dev This function can only be called when the vault is not paused
  * @param _amount The amount of coins to pay
  * @param _to The address to pay the coins to
  */
  function pay(uint256 _amount, address _to) public whenNotPaused nonReentrant {
    require(msg.sender == paymentContractAddress, "Vault: only payment contract can pay");
    require(_amount > 0, "Vault: _amount must be greater than zero");
    require(_amount <= vaultBalance, "Vault: _amount must be less than or equal to vault balance");
    require(_to != address(0), "Vault: to address cannot be zero");

    vaultBalance -= _amount;
    coin.transfer(_to, _amount);

    emit Pay(_to, _amount);
  }

  /**
   * @notice Withdraw coins from the vault to the owner
   * @dev This function can only be called by the owner
   * @dev This function can only be called when the vault is not paused
   * @param _amount The amount of coins to withdraw
   */
  function withdraw(uint256 _amount) public onlyOwner whenNotPaused nonReentrant {
    require(_amount > 0, "Vault: _amount must be greater than zero");
    require(_amount <= vaultBalance, "Vault: _amount must be less than or equal to vault balance");

    vaultBalance -= _amount;
    coin.transfer(msg.sender, _amount);

    emit Withdraw(msg.sender, _amount);
  }
}