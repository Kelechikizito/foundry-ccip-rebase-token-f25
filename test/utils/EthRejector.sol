// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract EthRejector {
    // Reject all ETH sent to this contract
    receive() external payable {
        revert("Rejecting ETH");
    }

    // // Function to deposit into Vault
    // function depositToVault(Vault vault, uint256 amount) external payable {
    //     vault.deposit{value: amount}();
    // }

    // // Function to redeem from Vault
    // function redeemFromVault(Vault vault, uint256 amount) external {
    //     vault.redeem(amount);
    // }
}
