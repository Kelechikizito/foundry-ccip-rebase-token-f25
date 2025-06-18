# CROSS-CHAIN REBASE TOKEN

1. A protocol that allows user to deposit into a vault and in return, receive rebase tokens that represent their underlying balance
2. Rebase Token -> balanceOf function is dynamic to show the changing balance with time.
   1. Balance increases linearly with time
   2. mint tokens to our users every time they perform an action(minting, burning, transferring, bridging)
3. Interest Rate
   1. Individually set an interest rate for each user based on some global interest rate of the protocol at the time the user deposits in to the vault
   2. This global interest rate can only decrease to incetivise/reward early adopters.
   3. Increase token adoption