// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {Vault} from "src/Vault.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EthRejector} from "test/utils/EthRejector.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;
    EthRejector private ethRejector;

    address public USER = makeAddr("user");
    address public USER_TWO = makeAddr("user_two");
    address public OWNER = makeAddr("owner");
    uint256 public constant INITIAL_ETH_ALLOWANCE = 1 ether;

    event InterestRateSet(uint256 newInterestRate);
    event Redeem(address indexed user, uint256 amount);

    function setUp() public {
        // Impersonate the 'owner' address for deployments and role granting
        vm.startPrank(OWNER);

        rebaseToken = new RebaseToken();

        // Deploy Vault: requires IRebaseToken.
        // Direct casting (IRebaseToken(rebaseToken)) is invalid.
        // Correct way: cast rebaseToken to address, then to IRebaseToken.
        vault = new Vault(IRebaseToken(address(rebaseToken)));

        // Grant the MINT_AND_BURN_ROLE to the Vault contract.
        // The grantMintAndBurnRole function expects an address.
        rebaseToken.grantMintAndBurnRole(address(vault));

        // Send 1 ETH to the Vault to simulate initial funds.
        // The target address must be cast to 'payable'.
        (bool success,) = payable(address(vault)).call{value: INITIAL_ETH_ALLOWANCE}("");
        // It's good practice to handle the success flag, though omitted for brevity here.

        // Stop impersonating the 'owner'
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardAmount}("");
        // vm.assume(success); // Optionally, assume the transfer succeeds
    }

    ////////////////////////////////////
    //   Fuzz/Stateless Fuzzing Tests //
    ///////////////////////////////////

    // Test if interest accrues linearly after a deposit.
    // 'amount' will be a fuzzed input. This is a stateless fuzzing.
    function testDepositLinear(uint256 amount) public {
        uint256 minimumBound = 1e5;
        // Constrain the fuzzed 'amount' to a practical range.
        // Min: 100,000 wei (1e5 wei), Max: type(uint96).max to avoid overflows.
        amount = bound(amount, minimumBound, type(uint96).max);

        // 1. User deposits 'amount' ETH
        vm.startPrank(USER); // Actions performed as 'user'
        vm.deal(USER, amount); // Give 'user' the 'amount' of ETH to deposit

        // TODO: Implement deposit logic:
        vault.deposit{value: amount}(); // Example

        // 2. TODO: Check initial rebase token balance for 'user'
        uint256 initialBalance = rebaseToken.balanceOf(USER);
        console.log("initial Balance: ", initialBalance);
        assertEq(initialBalance, amount);

        // 3. TODO: Warp time forward and check balance again
        uint256 timeDelta = 1 days; // Example
        vm.warp(block.timestamp + timeDelta);
        uint256 balanceAfterFirstWarp = rebaseToken.balanceOf(USER);
        uint256 interestFirstPeriod = balanceAfterFirstWarp - initialBalance;

        // 4. TODO: Warp time forward by the same amount and check balance again
        vm.warp(block.timestamp + timeDelta); // Warp by another 'timeDelta'
        uint256 balanceAfterSecondWarp = rebaseToken.balanceOf(USER);
        uint256 interestSecondPeriod = balanceAfterSecondWarp - balanceAfterFirstWarp;

        // TODO: Assert that interestFirstPeriod == interestSecondPeriod for linear accrual.
        assertApproxEqAbs(interestFirstPeriod, interestSecondPeriod, 1, "Interest accrual is not linear");

        vm.stopPrank(); // Stop impersonating 'user'
    }

    function testRedeemStraightAway(uint256 amount) public {
        // ARRANGE
        uint256 minimumBound = 1e5;
        amount = bound(amount, minimumBound, type(uint96).max);

        // ACT
        vm.startPrank(USER);
        vm.deal(USER, amount);
        vault.deposit{value: amount}();
        uint256 initialBalance = rebaseToken.balanceOf(USER);
        vault.redeem(type(uint256).max);
        uint256 userTokenBalanceAfterRedeem = rebaseToken.balanceOf(USER);

        // ASSERT
        assertEq(initialBalance, amount);
        assertEq(userTokenBalanceAfterRedeem, 0);
        assertEq(address(USER).balance, amount);
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 depositAmount, uint256 time) public {
        // ARRANGE
        uint256 minimumAmountBound = 1e5;
        uint256 minimumTimeBound = 1000 seconds;
        depositAmount = bound(depositAmount, minimumAmountBound, type(uint96).max);
        time = bound(time, minimumTimeBound, type(uint96).max);

        // ACT
        vm.deal(USER, depositAmount);
        vm.prank(USER);
        vault.deposit{value: depositAmount}();
        uint256 initialTokenBalance = rebaseToken.balanceOf(USER);

        vm.warp(block.timestamp + time);
        uint256 tokenBalanceAfterTimePassed = rebaseToken.balanceOf(USER);

        uint256 rewardAmount = tokenBalanceAfterTimePassed - depositAmount;

        vm.deal(OWNER, rewardAmount);
        vm.prank(OWNER);
        addRewardsToVault(rewardAmount);

        vm.prank(USER);
        vault.redeem(type(uint256).max);
        uint256 ethBalance = address(USER).balance;

        // ASSERT
        assertEq(ethBalance, tokenBalanceAfterTimePassed);
        assertGt(ethBalance, initialTokenBalance);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        // ARRANGE
        uint256 minimumBound = 1e5;
        amount = bound(amount, minimumBound, type(uint96).max);
        amountToSend = bound(amountToSend, minimumBound, amount);

        // ACT
        vm.deal(USER, amount);
        vm.prank(USER);
        vault.deposit{value: amount}();

        // The owner (deployer) reduces the global interest rate (`s_interestRate`) from its initial value (e.g., `5e10`) to a lower value (e.g., `4e10`).
        uint256 newInterestRate = 4e10;

        vm.prank(OWNER);
        rebaseToken.setInterestRate(newInterestRate);

        vm.prank(USER);
        rebaseToken.transfer(USER_TWO, amountToSend);

        uint256 userBalanceAfterTransfer = amount - amountToSend;
        uint256 userTwoBalanceAfterTransfer = amountToSend;

        // ASSERT
        assertEq(rebaseToken.balanceOf(USER), userBalanceAfterTransfer);
        assertEq(rebaseToken.balanceOf(USER_TWO), userTwoBalanceAfterTransfer);
        // Check the user interest rate has been inherited (5e10 not 4e10)
        assertEq(rebaseToken.getUserInterestRate(USER), 5e10);
        assertEq(rebaseToken.getUserInterestRate(USER_TWO), 5e10);
    }

    function testTransferFromFullBalance(uint256 amount) public {
        // ARRANGE
        uint256 minimumBound = 1e5;
        amount = bound(amount, minimumBound, type(uint96).max);

        // ACT
        vm.deal(USER, amount);
        vm.prank(USER);
        vault.deposit{value: amount}();

        vm.prank(USER);
        rebaseToken.transfer(USER_TWO, amount);

        uint256 userBalanceAfterTransfer = amount - amount;
        uint256 userTwoBalanceAfterTransfer = amount;

        // ASSERT
        assertEq(rebaseToken.balanceOf(USER), userBalanceAfterTransfer);
        assertEq(rebaseToken.balanceOf(USER_TWO), userTwoBalanceAfterTransfer);
    }

    function testTransferFromSetsRecipientRateAndTransfersCorrectly(uint256 amount, uint256 transferAmount) public {
        // ARRANGE
        uint256 minimumBound = 1e5;
        amount = bound(amount, minimumBound, type(uint96).max);
        transferAmount = bound(transferAmount, minimumBound, amount);

        // ACT
        vm.deal(USER, amount); // Deal and deposit ETH for USER
        vm.prank(USER);
        vault.deposit{value: amount}();

        vm.prank(USER); // USER approves USER_TWO to spend their tokens
        rebaseToken.approve(USER_TWO, transferAmount); // You have to approve USER_TWO as the spender for transferFrom to work

        vm.prank(USER_TWO); // USER_TWO calls transferFrom to take tokens from USER
        rebaseToken.transferFrom(USER, USER_TWO, transferAmount);

        // ASSERT
        assertEq(rebaseToken.balanceOf(USER), amount - transferAmount);
        assertEq(rebaseToken.balanceOf(USER_TWO), transferAmount);
        // ASSERT interest rate was inherited correctly
        assertEq(rebaseToken.getUserInterestRate(USER_TWO), rebaseToken.getUserInterestRate(USER));
    }

    function testGetPrincipalAmount(uint256 amount) public {
        // ARRANGE
        uint256 minimumBound = 1e5;
        amount = bound(amount, minimumBound, type(uint96).max);

        // ACT
        vm.startPrank(USER);
        vm.deal(USER, amount);
        vault.deposit{value: amount}();
        uint256 initialPrincipalBalance = rebaseToken.principalBalanceOf(USER);
        assertEq(initialPrincipalBalance, amount);
        vm.stopPrank();

        uint256 timePassed = 1000 seconds;
        vm.warp(block.timestamp + timePassed);

        // ASSERT
        uint256 principalBalanceAfterTimePassed = rebaseToken.principalBalanceOf(USER);
        assertEq(principalBalanceAfterTimePassed, initialPrincipalBalance); // After warping time
    }

    function testMintByVault(uint256 amount) public {
        // ARRANGE
        uint256 minimumBound = 1e5;
        amount = bound(amount, minimumBound, type(uint96).max);

        // ACT
        vm.prank(address(vault));
        rebaseToken.mint(USER, amount, rebaseToken.getInterestRate());

        // ASSERT
        assertEq(rebaseToken.balanceOf(USER), amount);
        assertEq(rebaseToken.principalBalanceOf(USER), amount);
        assertEq(rebaseToken.getUserInterestRate(USER), rebaseToken.getInterestRate());
        assertEq(rebaseToken.getUserLastUpdatedTimestamp(USER), block.timestamp);
    }

    function testBurnByVault(uint256 amount) public {
        // ARRANGE
        uint256 minimumBound = 1e5;
        amount = bound(amount, minimumBound, type(uint96).max);

        // ACT
        vm.deal(USER, amount);
        vm.prank(USER);
        vault.deposit{value: amount}();
        vm.prank(address(vault));
        rebaseToken.burn(USER, amount);

        // ASSERT
        assertEq(rebaseToken.balanceOf(USER), 0);
        assertEq(rebaseToken.principalBalanceOf(USER), 0);
    }

    function testMintAccruedInterestWithInterest(uint256 amount) public {
        // ARRANGE
        uint256 minimumBound = 1e5;
        amount = bound(amount, minimumBound, type(uint96).max);

        // ACT
        vm.deal(USER, amount);
        vm.prank(USER);
        vault.deposit{value: amount}();
        vm.warp(block.timestamp + 1 days);
        vm.prank(address(vault));
        rebaseToken.mint(USER, 0, rebaseToken.getInterestRate()); // Triggers _mintAccruedInterest
        uint256 tokenBalanceAfter = rebaseToken.balanceOf(USER);

        // ASSERT
        assertGt(tokenBalanceAfter, amount);
    }

    ////////////////////////////
    //   Access Control Tests //
    ////////////////////////////

    function testCannotSetInterestRate(uint256 newInterestRate) public {
        // ACT / ASSERT
        vm.startPrank(USER);
        vm.expectPartialRevert(bytes4(Ownable.OwnableUnauthorizedAccount.selector));
        rebaseToken.setInterestRate(newInterestRate);
        vm.stopPrank();
    }

    function testCannotCallMintandBurn() public {
        // ARRANGE
        uint256 mintAmount = 100;
        uint256 burnAmount = 70;

        // ACT / ASSERT
        vm.prank(USER);
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.mint(USER, mintAmount, rebaseToken.getInterestRate());

        vm.prank(USER);
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.burn(USER, burnAmount);
    }

    function testOwnerCanGrantMintAndBurnRole() public {
        // ARRANGE / ACT
        vm.prank(OWNER);
        rebaseToken.grantMintAndBurnRole(USER_TWO);

        // ASSERT
        assertTrue(rebaseToken.hasRole(rebaseToken.getMintAndBurnRole(), USER_TWO));
    }

    function testNonOwnerCannotGrantMintAndBurnRole() public {
        // ACT & ASSERT
        vm.prank(USER);
        vm.expectRevert();
        rebaseToken.grantMintAndBurnRole(USER_TWO);
    }

    ////////////////////////////
    //   Events Tests         //
    ////////////////////////////

    function testSetInterestRateAndEmitsEvent() public {
        // ARRANGE
        uint256 amount = 1 ether;

        // ACT / ASSERT
        vm.deal(USER, amount);
        vm.prank(USER);
        vault.deposit{value: amount}();

        uint256 newInterestRate = 4e10;

        vm.prank(OWNER);
        vm.expectEmit(false, false, false, false, address(rebaseToken));
        emit InterestRateSet(newInterestRate);
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testRedeemAndEmitsEvent() public {
        // ARRANGE
        uint256 amount = 1 ether;

        // ACT / ASSERT
        vm.startPrank(USER);
        vm.deal(USER, amount);
        vault.deposit{value: amount}();
        vm.expectEmit(true, false, false, false, address(vault));
        emit Redeem(USER, amount);
        vault.redeem(type(uint256).max);
        vm.stopPrank();
    }

    ////////////////////////////
    //   MaxTransfer Tests    //
    ////////////////////////////

    function testTransferWithMaxAmount() public {
        // ARRANGE
        uint256 depositAmount = 1 ether;

        // ACT
        vm.deal(USER, depositAmount);
        vm.prank(USER);
        vault.deposit{value: depositAmount}();

        uint256 userInitialTokenBalance = rebaseToken.balanceOf(USER);

        vm.prank(USER);
        rebaseToken.transfer(USER_TWO, type(uint256).max);

        // ASSERT
        assertEq(rebaseToken.balanceOf(USER), 0);
        assertEq(rebaseToken.balanceOf(USER_TWO), userInitialTokenBalance);
    }

    function testTransferFromWithMaxAmount() public {
        // ARRANGE
        uint256 depositAmount = 1 ether;

        // ACT
        vm.deal(USER, depositAmount);
        vm.prank(USER);
        vault.deposit{value: depositAmount}();
        uint256 userInitialTokenBalance = rebaseToken.balanceOf(USER);
        // Approve USER_TWO to spend all tokens
        vm.prank(USER);
        rebaseToken.approve(USER_TWO, type(uint256).max);
        vm.prank(USER_TWO);
        rebaseToken.transferFrom(USER, USER_TWO, type(uint256).max);

        // ASSERT
        assertEq(rebaseToken.balanceOf(USER), 0);
        assertEq(rebaseToken.balanceOf(USER_TWO), userInitialTokenBalance);
    }

    ///////////////////////////////////
    //   Interest Rate Tests         //
    //////////////////////////////////

    function testRevertsIfInterestRateTriesToIncrease() public {
        // ARRANGE
        uint256 oldInterestRate = 5e10;
        uint256 newInterestRate = 6e10;

        // ACT / ASSERT
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector, oldInterestRate, newInterestRate
            )
        );
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testCalculateUserAccumulatedInterestSinceLastUpdate() public {
        // ARRANGE
        uint256 precisionFactor = 1e18;
        uint256 depositAmount = 1 ether;
        uint256 userInterestRate = rebaseToken.getInterestRate(); // Should be 5e10 as initialized

        // ACT
        vm.deal(USER, depositAmount); // Step 1: Deal and deposit
        vm.prank(USER);
        vault.deposit{value: depositAmount}();

        uint256 timeElapsed = 1 days; // Step 2: Warp forward in time
        vm.warp(block.timestamp + timeElapsed);

        uint256 actualInterestFactor = rebaseToken.getCalculatedUserAccumulatedInterestSinceLastUpdate(USER); // Step 3: Call function to get actual interest factor

        uint256 expectedFractionalInterest = userInterestRate * timeElapsed; // Step 4: Manually compute expected value
        uint256 expectedInterestFactor = precisionFactor + expectedFractionalInterest;

        // ASSERT
        assertApproxEqAbs(
            actualInterestFactor, expectedInterestFactor, 1, "Accumulated interest factor does not match expected"
        ); // Step 5: Assert they are approximately equal
    }

    ///////////////////////////////////
    //   Edge-Cases Tests         /////
    //////////////////////////////////

    function testRevertsIfDepositZeroAmount() public {
        // ARRANGE
        uint256 amount = 0;

        // ACT
        vm.startPrank(USER);
        vm.deal(USER, amount);

        // ASSERT
        vm.expectRevert(Vault.Vault__DepositAmountIsZero.selector);
        vault.deposit{value: amount}();
        vm.stopPrank();
    }

    function testRevertsIfRedeemMoreThanDeposited() public {
        // ARRANGE
        uint256 amount = 1 ether;

        // ACT / ASSERT
        vm.startPrank(USER);
        vm.deal(USER, amount);
        vault.deposit{value: amount}();
        vm.expectRevert();
        vault.redeem(amount + 1 ether);
        vm.stopPrank();
    }

    function testRedeemRevertsOnEthTransfer() public {
        // ARRANGE: Create a contract that rejects ETH
        address rejectingContract = address(new EthRejector());
        uint256 depositAmount = 1 ether;
        vm.deal(rejectingContract, depositAmount);
        vm.prank(rejectingContract);
        vault.deposit{value: depositAmount}();

        // ACT / ASSERT
        vm.prank(rejectingContract);
        vm.expectRevert(Vault.Vault__RedeemFailed.selector);
        vault.redeem(depositAmount);
    }

    function testTransferZeroAmount() public {
        // ARRANGE
        uint256 depositAmount = 1 ether;

        // ACT
        vm.deal(USER, depositAmount);
        vm.prank(USER);
        vault.deposit{value: depositAmount}();
        uint256 initialBalanceUser = rebaseToken.balanceOf(USER);
        uint256 initialBalanceUserTwo = rebaseToken.balanceOf(USER_TWO);
        vm.prank(USER);
        rebaseToken.transfer(USER_TWO, 0);

        // ASSERT
        assertEq(rebaseToken.balanceOf(USER), initialBalanceUser);
        assertEq(rebaseToken.balanceOf(USER_TWO), initialBalanceUserTwo);
    }

    ////////////////////////////
    //  Constructor  Tests   ///
    ////////////////////////////
    function testConstructorInitializesRebaseToken() public {
        // ARRANGE / ACT
        IRebaseToken expectedToken = IRebaseToken(address(rebaseToken));
        Vault testVault = new Vault(expectedToken);

        // ASSERT
        assertEq(address(testVault.getRebaseToken()), address(expectedToken));
    }

    function testConstructorSetsOwner() public view {
        assertEq(rebaseToken.owner(), OWNER);
    }

    ////////////////////////////
    //   Getter Function Tests //
    ////////////////////////////
    function testGetRebaseTokenAddress() public view {
        assertEq(vault.getRebaseTokenAddress(), address(rebaseToken));
    }

    function testGetUserLastUpdatedTimestamp() public view {
        assertEq(rebaseToken.getUserLastUpdatedTimestamp(USER), 0);
    }

    function testGetInterestRate() public view {
        uint256 interestRate = 5e10;
        assertEq(rebaseToken.getInterestRate(), interestRate);
    }

    function testGetMintAndBurnRole() public view {
        bytes32 role = rebaseToken.getMintAndBurnRole();
        assertEq(role, keccak256("MINT_AND_BURN_ROLE"));
    }
}
