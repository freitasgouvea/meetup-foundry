/// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

/**
* @title CCIP Adapter contract
* @notice This contract is used to interact with the Chainlink CCIP
*/
contract CCIPAdapter is Ownable, Pausable, ReentrancyGuard {
    address public paymentContractAddress;

    IRouterClient private router;
    IERC20 public link;

    bool public initialized;

    /// Fuji testnet chain selector
    uint64 public constant CURRENT_CHAIN = 14767482510784806043;

    mapping(uint64 => bool) public allowlistedChains;

    event Send(
        bytes32 indexed messageId, // The unique ID of the message.
        uint64 indexed destinationChainSelector, // The chain selector of the destination chain.
        address receiver, // The address of the receiver on the destination chain.
        address token, // The token address that was transferred.
        uint256 tokenAmount, // The token amount that was transferred.
        address feeToken, // the token address used to pay CCIP fees.
        uint256 fees // The fees paid for sending the message.
    );

    /**
    * @notice Create a new CCIPAdapter
    * @dev The CCIPAdapter is paused by default
    * @dev The owner of the CCIPAdapter is the deployer
    */
    constructor() Ownable(msg.sender) {
        _pause();
    }

    /**
    * @notice Initialize the CCIP Adapter
    * @dev This function can only be called once
    * @param _linkAddress The address of the link contract
    * @param _payerContractAddress The address of the payer contract
    * @param _router The address of the CCIP router contract
    */
    function initialize(
        address _linkAddress, 
        address _payerContractAddress, 
        address _router
    ) public onlyOwner {
        require(!initialized, "Vault: already initialized");
        require(_payerContractAddress != address(0), "Vault: payer contract address cannot be zero");
        require(_linkAddress != address(0), "Vault: link address cannot be zero");
        require(_router != address(0), "Vault: router address cannot be zero");

        link = IERC20(_linkAddress);
        paymentContractAddress = _payerContractAddress;
        router = IRouterClient(_router);

        // add mumbai for tests
        allowlistedChains[14767482510784806043] = true;

        _unpause();

        initialized = true;
    }

    /// @dev Modifier that checks if the chain with the given destinationChainSelector is allowlisted.
    /// @param _destinationChainSelector The selector of the destination chain.
    modifier onlyAllowlistedChain(uint64 _destinationChainSelector) {
        require (_destinationChainSelector != CURRENT_CHAIN, "CCIPAdapter: Cannot send to current chain");
        require(allowlistedChains[_destinationChainSelector], "CCIPAdapter: Chain not allowlisted");
        _;
    }

    /// @dev Updates the allowlist status of a destination chain for transactions.
    /// @notice This function can only be called by the owner.
    /// @param _destinationChainSelector The selector of the destination chain to be updated.
    /// @param allowed The allowlist status to be set for the destination chain.
    function allowlistDestinationChain(
        uint64 _destinationChainSelector,
        bool allowed
    ) external onlyOwner {
        allowlistedChains[_destinationChainSelector] = allowed;
    }

    function send(
        address _token, 
        uint256 _amount, 
        address _to, 
        uint64 _destinationChainSelector
    ) external whenNotPaused nonReentrant onlyAllowlistedChain(_destinationChainSelector) returns (bytes32) {
        require(_amount > 0, "CCIPAdapter: _amount must be greater than zero");
        require(_to != address(0), "CCIPAdapter: _to address cannot be zero");
        require(_token != address(0), "CCIPAdapter: _token address cannot be zero");
        require( IERC20(_token).transfer(address(this), _amount), "CCIPAdapter: transfer failed");

        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _to,
            _token,
            _amount,
            address(link)
        );

        uint256 fees = router.getFee(
            _destinationChainSelector,
            evm2AnyMessage
        );

        require(link.balanceOf(address(this)) >= fees, "CCIPAdapter: insufficient link balance");

        link.approve(address(router), fees);
        IERC20(_token).approve(address(router), _amount);

        bytes32 messageId = router.ccipSend(
            _destinationChainSelector,
            evm2AnyMessage
        );

        emit Send(
            messageId,
            _destinationChainSelector,
            _to,
            _token,
            _amount,
            address(link),
            fees
        );

        return messageId;
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

    /// @notice Allows the owner of the contract to withdraw all tokens of a specific ERC20 token.
    /// @dev This function can only be called by the owner.
    /// @dev This function can only be called when the contract is not paused.
    /// @param _token The contract address of the ERC20 token to be withdrawn.
    function withdrawToken(
        address _token
    ) public onlyOwner whenNotPaused nonReentrant {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        require(amount > 0, "CCIPAdapter: Nothing to withdraw");
        IERC20(_token).transfer(msg.sender, amount);
    }
}