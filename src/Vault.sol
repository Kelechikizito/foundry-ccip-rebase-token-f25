// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Layout of the contract file:
// version
// imports
// interfaces, libraries, contract
// errors

// Inside Contract:
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private

// view & pure functions

import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";

contract Vault {
    // Core Requirements:
    // 1. Store the address of the RebaseToken contract (passed in constructor).
    // 2. Implement a deposit function:
    //    - Accepts ETH from the user.
    //    - Mints RebaseTokens to the user, equivalent to the ETH sent (1:1 peg initially).
    // 3. Implement a redeem function:
    //    - Burns the user's RebaseTokens.
    //    - Sends the corresponding amount of ETH back to the user.
    // 4. Implement a mechanism to add ETH rewards to the vault.

    ///////////////////
    /// Errors      ///
    ///////////////////
    error Vault__DepositAmountIsZero();
    error Vault__RedeemFailed();

    ////////////////////////
    //   State Variables  //
    ////////////////////////
    IRebaseToken private immutable i_rebaseToken;

    ////////////////////////
    //   Events        /////
    ////////////////////////
    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    ///////////////////
    //   Functions   //
    ///////////////////
    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    //////////////////////////
    // Receive  Functions   //
    //////////////////////////
    receive() external payable {}

    ////////////////////////////
    //   External Functions   //
    ////////////////////////////
    /**
     * @notice Allows a user to deposit ETH and receive an equivalent amount of RebaseTokens.
     * @dev The amount of ETH sent with the transaction (msg.value) determines the amount of tokens minted.
     * Assumes a 1:1 peg for ETH to RebaseToken for simplicity in this version.
     */
    function deposit() external payable {
        // The amount of ETH sent is msg.value
        // The user making the call is msg.sender
        uint256 amountToMint = msg.value;

        // Ensure some ETH is actually sent: CHECKS
        if (amountToMint == 0) {
            revert Vault__DepositAmountIsZero();
        }

        // Call the mint function on the RebaseToken contract: EFFECTS
        i_rebaseToken.mint(msg.sender, amountToMint);

        // Emit an event to log the deposit: INTERACTIONS
        emit Deposit(msg.sender, amountToMint);
    }

    /**
     * @notice Allows a user to burn their RebaseTokens and receive a corresponding amount of ETH.
     * @param _amount The amount of RebaseTokens to redeem.
     * @dev Follows Checks-Effects-Interactions pattern. Uses low-level .call for ETH transfer.
     */
    function redeem(uint256 _amount) external {
        uint256 amountToRedeem = _amount;

        if (_amount == type(uint256).max) {
            amountToRedeem = i_rebaseToken.balanceOf(msg.sender); // Set amount to full current balance
        }

        // 1. Effects (State changes occur first)
        // Burn the specified amount of tokens from the caller (msg.sender)
        // The RebaseToken's burn function should handle checks for sufficient balance.
        i_rebaseToken.burn(msg.sender, amountToRedeem);

        // 2. Interactions (External calls / ETH transfer last)
        // Send the equivalent amount of ETH back to the user
        (bool success,) = payable(msg.sender).call{value: amountToRedeem}("");

        // Check if the ETH transfer succeeded
        if (!success) {
            revert Vault__RedeemFailed(); // Use the custom error
        }

        // Emit an event logging the redemption
        emit Redeem(msg.sender, _amount);
    }

    ///////////////////////////////////////////
    //   Public & External View Functions   //
    //////////////////////////////////////////
    /**
     * @notice Gets the address of the RebaseToken contract associated with this vault.
     * @return The address of the RebaseToken.
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }

    function getRebaseToken() external view returns (IRebaseToken) {
        return i_rebaseToken;
    }
}
