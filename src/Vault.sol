/// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

/**
* @title Vault contract
* @notice This contract holds the coins deposited by the users
* @notice The payment contract can withdraw coins from the vault
*/
contract Vault is Ownable, Pausable, ReentrancyGuard {
    // current chain selector Fuji testnet
    uint64 public constant CURRENT_CHAIN = 0;

    bool public initialized;

    IERC20 public coin;
    IERC20 public link;

    address public paymentContractAddress;

    uint256 public vaultBalance;
    uint256 public vaultLinkBalance;
  
    mapping(uint64 => bool) public allowlistedChains;
    IRouterClient private router;

    event DepositCoin(address indexed from, uint256 amount, address indexed coin);
    event DepositLink(address indexed from, uint256 amount, address indexed coin);
    event Pay(address indexed to, uint256 amount, address indexed coin, uint64 indexed destinationChainSelector);
    event WithdrawCoin(address indexed to, uint256 amount, address indexed coin);
    event WithdrawLink(address indexed to, uint256 amount, address indexed coin);

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
    * @param _linkAddress The address of the link contract
    * @param _payerContractAddress The address of the payer contract
    * @param _router The address of the CCIP router contract
    */
    function initialize(address _coinAddress, address _linkAddress, address _payerContractAddress, address _router) public onlyOwner {
        require(!initialized, "Vault: already initialized");
        require(_coinAddress != address(0), "Vault: coin address cannot be zero");
        require(_payerContractAddress != address(0), "Vault: payer contract address cannot be zero");
        require(_linkAddress != address(0), "Vault: link address cannot be zero");
        require(_router != address(0), "Vault: router address cannot be zero");

        // coin = IERC20(_coinAddress);
        coin = IERC20(0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846);

        // link = IERC20(_linkAddress);
        link = IERC20(0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846);

        // paymentContractAddress = _payerContractAddress;
        paymentContractAddress = 0xDB09b1B61D1db17764AFC7F2A16245CC3258fF36;

        // router = IRouterClient(_router);
        router = IRouterClient(0x554472a2720E5E7D5D3C817529aBA05EEd5F82D8);

        vaultBalance = 0;
        vaultLinkBalance = 0;

        allowlistedChains[CURRENT_CHAIN] = true;

        // add mumbai for tests
        allowlistedChains[14767482510784806043] = true;

        _unpause();

        initialized = true;
    }

    /**
    * @notice Deposit coins into the vault
    * @dev This function can only be called when the vault is not paused
    * @param _amount The amount of coins to deposit
    */
    function depositCoin(uint256 _amount) public whenNotPaused nonReentrant {
        require(_amount > 0, "Vault: _amount must be greater than zero");
        require (coin.allowance(msg.sender, address(this)) >= _amount, "Vault: allowance must be greater than or equal to _amount");

        vaultBalance += _amount;
        coin.transferFrom(msg.sender, address(this), _amount);

        emit DepositCoin(msg.sender, _amount, address(coin));
    }

    /**
    * @notice Deposit link into the vault
    * @dev This function can only be called when the vault is not paused
    * @param _amount The amount of link to deposit
    */
    function depositLink(uint256 _amount) public whenNotPaused nonReentrant {
        require(_amount > 0, "Vault: _amount must be greater than zero");
        require (link.allowance(msg.sender, address(this)) >= _amount, "Vault: allowance must be greater than or equal to _amount");

        vaultLinkBalance += _amount;
        link.transferFrom(msg.sender, address(this), _amount);

        emit DepositLink(msg.sender, _amount, address(link));
    }

    /**
    * @notice Pay coins from the vault
    * @dev This function can only be called by the payment contract
    * @dev This function can only be called when the vault is not paused
    * @param _amount The amount of coins to pay
    * @param _to The address to pay the coins to
    * @param _destinationChainSelector The destination chain selector
    */
    function pay(uint256 _amount, address _to, uint64 _destinationChainSelector) public whenNotPaused nonReentrant {
        require(msg.sender == paymentContractAddress, "Vault: only payment contract can pay");
        require(_amount > 0, "Vault: _amount must be greater than zero");
        require(_amount <= vaultBalance, "Vault: _amount must be less than or equal to vault balance");
        require(_to != address(0), "Vault: to address cannot be zero");
        require(allowlistedChains[_destinationChainSelector], "Vault: destination chain must be allowlisted");

        if (_destinationChainSelector == CURRENT_CHAIN) {
            vaultBalance -= _amount;
            coin.transfer(_to, _amount);
        } else {
            Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
                _to,
                address(coin),
                _amount,
                address(link)
            );
    
            uint256 fees = router.getFee(
                _destinationChainSelector,
                evm2AnyMessage
            );

            require(fees <= vaultLinkBalance, "Vault: fees must be less than or equal to vault LINK balance");
    
            vaultBalance -= _amount;
            vaultLinkBalance -= fees;
    
            link.approve(address(router), fees);
            coin.approve(address(router), _amount);
    
            bytes32 messageId = router.ccipSend{value: fees}(
                _destinationChainSelector,
                evm2AnyMessage
            );
        }

        emit Pay(_to, _amount, address(coin), _destinationChainSelector);
    }

    /**
    * @notice Withdraw coins from the vault to the owner
    * @dev This function can only be called by the owner
    * @dev This function can only be called when the vault is not paused
    * @param _amount The amount of coins to withdraw
    */
    function withdrawCoin(uint256 _amount) public onlyOwner whenNotPaused nonReentrant {
        require(_amount > 0, "Vault: _amount must be greater than zero");
        require(_amount <= vaultBalance, "Vault: _amount must be less than or equal to vault COIN balance");

        vaultBalance -= _amount;
        coin.transfer(msg.sender, _amount);

        emit WithdrawCoin(msg.sender, _amount, address(coin));
    }

    /**
    * @notice Withdraw LINK from the vault to the owner
    * @dev This function can only be called by the owner
    * @dev This function can only be called when the vault is not paused
    * @param _amount The amount of LINK to withdraw
    */
    function withdrawLink(uint256 _amount) public onlyOwner whenNotPaused nonReentrant {
        require(_amount > 0, "Vault: _amount must be greater than zero");
        require(_amount <= vaultLinkBalance, "Vault: _amount must be less than or equal to vault LINK balance");

        vaultLinkBalance -= _amount;
        link.transfer(msg.sender, _amount);

        emit WithdrawLink(msg.sender, _amount, address(link));
    }

    /// @notice Construct a CCIP message.
    /// @dev This function will create an EVM2AnyMessage struct with all the necessary information for tokens transfer.
    /// @param _receiver The address of the receiver.
    /// @param _token The token to be transferred.
    /// @param _amount The amount of the token to be transferred.
    /// @param _feeTokenAddress The address of the token used for fees. Set address(0) for native gas.
    /// @return Client.EVM2AnyMessage Returns an EVM2AnyMessage struct which contains information for sending a CCIP message.
    function _buildCCIPMessage(
        address _receiver,
        address _token,
        uint256 _amount,
        address _feeTokenAddress
    ) internal pure returns (Client.EVM2AnyMessage memory) {
        // Set the token amounts
        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: _token,
            amount: _amount
        });

        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        return
            Client.EVM2AnyMessage({
                receiver: abi.encode(_receiver), // ABI-encoded receiver address
                data: "", // No data
                tokenAmounts: tokenAmounts, // The amount and type of token being transferred
                extraArgs: Client._argsToBytes(
                    // Additional arguments, setting gas limit to 0 as we are not sending any data and non-strict sequencing mode
                    Client.EVMExtraArgsV1({gasLimit: 0, strict: false})
                ),
                // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees
                feeToken: _feeTokenAddress
            });
    }
}