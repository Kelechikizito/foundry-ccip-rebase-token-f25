// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract BridgeTokensScript is Script {
    function run(
        address receiverAddress,
        uint64 destinationChainSelector,
        uint256 amountToSend,
        address routerAddress,
        address tokenToSendAddress,
        address linkTokenAddress
    ) public {
        // Inside the run function, before vm.startBroadcast() or just after for declaration
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: tokenToSendAddress, // The address of the token being sent
            amount: amountToSend // The amount of the token to send
        });
        // Cast routerAddress to IRouterClient to call its functions
        vm.startBroadcast();
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiverAddress), // Receiver address MUST be abi.encode()'d
            data: "", // Empty bytes as we are sending no data payload
            tokenAmounts: tokenAmounts, // The array of token transfers defined above
            feeToken: linkTokenAddress, // Address of the token used for CCIP fees (LINK)
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})) // Encoded extra arguments
        });
        uint256 ccipFee = IRouterClient(routerAddress).getFee(destinationChainSelector, message);
        // Approve the CCIP Router to spend the fee token (LINK)
        IERC20(linkTokenAddress).approve(routerAddress, ccipFee);

        // Approve the CCIP Router to spend the token being bridged
        IERC20(tokenToSendAddress).approve(routerAddress, amountToSend);
        // Client.EVM2AnyMessage message = Client.EVM2AnyMessage({});
        IRouterClient(routerAddress).ccipSend(destinationChainSelector, message);
        vm.stopBroadcast();
    }
}
