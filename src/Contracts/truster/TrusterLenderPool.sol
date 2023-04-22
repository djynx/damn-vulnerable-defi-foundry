// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Address} from "openzeppelin-contracts/utils/Address.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/security/ReentrancyGuard.sol";

/**
 * @title TrusterLenderPool
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 */
contract TrusterLenderPool is ReentrancyGuard {
    using Address for address;

    IERC20 public immutable damnValuableToken;

    error NotEnoughTokensInPool();
    error FlashLoanHasNotBeenPaidBack();

    constructor(address tokenAddress) {
        damnValuableToken = IERC20(tokenAddress);
    }
    // check the balance from token side
    // if not borrow amount > current token balance cont.
    // transfer
    // func call
    // if balanceafter <

    function flashLoan(uint256 borrowAmount, address borrower, address target, bytes calldata data)
        external
        nonReentrant
    {
        uint256 balanceBefore = damnValuableToken.balanceOf(address(this));
        if (balanceBefore < borrowAmount) revert NotEnoughTokensInPool();

        damnValuableToken.transfer(borrower, borrowAmount);
        target.functionCall(data);

        uint256 balanceAfter = damnValuableToken.balanceOf(address(this));
        if (balanceAfter < balanceBefore) revert FlashLoanHasNotBeenPaidBack();
    }
}
