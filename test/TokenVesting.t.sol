// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {TokenVesting} from "../src/TokenVesting.sol";

// Simple ERC20 mock
contract MockERC20 {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient balance");
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

contract TokenVestingTest is Test {
    TokenVesting public vesting;
    MockERC20 public token;

    address owner = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    uint256 constant TOTAL = 1000e18;
    uint256 constant START_OFFSET = 100;
    uint256 constant CLIFF_DURATION = 365 days;
    uint256 constant DURATION = 4 * 365 days; // 4 years

    function setUp() public {
        token = new MockERC20();
        vesting = new TokenVesting(address(token));

        // Fund vesting contract
        token.mint(address(vesting), 10_000e18);
    }

    function test_CreateVestingSchedule() public {
        uint256 start = block.timestamp + START_OFFSET;
        bytes32 id = vesting.createVestingSchedule(alice, start, CLIFF_DURATION, DURATION, TOTAL, true);

        TokenVesting.VestingSchedule memory s = vesting.getVestingSchedule(id);
        assertEq(s.beneficiary, alice);
        assertEq(s.amountTotal, TOTAL);
        assertEq(s.cliff, start + CLIFF_DURATION);
        assertEq(s.duration, DURATION);
        assertTrue(s.revocable);
        assertFalse(s.revoked);
        assertEq(s.released, 0);
    }

    function test_CannotReleaseBeforeCliff() public {
        uint256 start = block.timestamp;
        bytes32 id = vesting.createVestingSchedule(alice, start, CLIFF_DURATION, DURATION, TOTAL, false);

        // Warp to just before cliff
        vm.warp(block.timestamp + CLIFF_DURATION - 1);

        vm.prank(alice);
        vm.expectRevert("nothing to release");
        vesting.release(id);
    }

    function test_ReleaseAfterCliff() public {
        uint256 start = block.timestamp;
        bytes32 id = vesting.createVestingSchedule(alice, start, CLIFF_DURATION, DURATION, TOTAL, false);

        // Warp to exactly cliff
        vm.warp(start + CLIFF_DURATION);

        uint256 releasable = vesting.computeReleasableAmount(id);
        assertGt(releasable, 0);

        uint256 before = token.balanceOf(alice);
        vm.prank(alice);
        vesting.release(id);

        assertGt(token.balanceOf(alice), before);
    }

    function test_ReleaseLinear() public {
        uint256 start = block.timestamp;
        bytes32 id = vesting.createVestingSchedule(alice, start, CLIFF_DURATION, DURATION, TOTAL, false);

        // Warp to halfway through vesting (2 years)
        vm.warp(start + DURATION / 2);

        uint256 releasable = vesting.computeReleasableAmount(id);
        // Should be ~50% of total (since cliff < halfway)
        assertApproxEqRel(releasable, TOTAL / 2, 0.01e18); // 1% tolerance

        vm.prank(alice);
        vesting.release(id);

        assertApproxEqRel(token.balanceOf(alice), TOTAL / 2, 0.01e18);
    }

    function test_RevokeReturnsUnvestedTokens() public {
        uint256 start = block.timestamp;
        bytes32 id = vesting.createVestingSchedule(alice, start, CLIFF_DURATION, DURATION, TOTAL, true);

        // Warp past cliff
        vm.warp(start + CLIFF_DURATION + 30 days);

        uint256 ownerBefore = token.balanceOf(owner);
        uint256 releasable = vesting.computeReleasableAmount(id);

        vesting.revoke(id);

        TokenVesting.VestingSchedule memory s = vesting.getVestingSchedule(id);
        assertTrue(s.revoked);

        // Alice got her vested portion
        assertApproxEqRel(token.balanceOf(alice), releasable, 0.01e18);

        // Owner got back unvested portion
        uint256 unvested = TOTAL - releasable;
        assertApproxEqRel(token.balanceOf(owner) - ownerBefore, unvested, 0.01e18);
    }

    function test_CannotRevokeNonRevocable() public {
        uint256 start = block.timestamp;
        bytes32 id = vesting.createVestingSchedule(alice, start, CLIFF_DURATION, DURATION, TOTAL, false);

        vm.expectRevert("not revocable");
        vesting.revoke(id);
    }

    function test_ComputeScheduleId() public view {
        bytes32 id0 = vesting.computeVestingScheduleId(alice, 0);
        bytes32 id1 = vesting.computeVestingScheduleId(alice, 1);
        assertTrue(id0 != id1);

        bytes32 idBob = vesting.computeVestingScheduleId(bob, 0);
        assertTrue(id0 != idBob);
    }
}
