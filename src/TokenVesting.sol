// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract TokenVesting {
    event VestingScheduleCreated(bytes32 indexed scheduleId, address indexed beneficiary, uint256 amount);
    event TokensReleased(bytes32 indexed scheduleId, address indexed beneficiary, uint256 amount);
    event VestingRevoked(bytes32 indexed scheduleId, address indexed beneficiary, uint256 refunded);

    struct VestingSchedule {
        address beneficiary;
        uint256 cliff;      // timestamp at which cliff ends
        uint256 start;      // vesting start timestamp
        uint256 duration;   // total vesting duration in seconds
        uint256 amountTotal;
        uint256 released;
        bool revocable;
        bool revoked;
    }

    address public owner;
    IERC20 public immutable token;

    mapping(bytes32 => VestingSchedule) private vestingSchedules;
    mapping(address => uint256) public holdersVestingCount;

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address _token) {
        require(_token != address(0), "invalid token");
        token = IERC20(_token);
        owner = msg.sender;
    }

    /// @notice Create a new vesting schedule
    /// @param beneficiary address that will receive vested tokens
    /// @param start unix timestamp when vesting starts
    /// @param cliffDuration seconds until cliff (no tokens before cliff)
    /// @param duration total vesting duration in seconds (from start)
    /// @param amount total tokens to vest
    /// @param revocable whether owner can revoke unvested tokens
    function createVestingSchedule(
        address beneficiary,
        uint256 start,
        uint256 cliffDuration,
        uint256 duration,
        uint256 amount,
        bool revocable
    ) external onlyOwner returns (bytes32 scheduleId) {
        require(beneficiary != address(0), "invalid beneficiary");
        require(duration > 0, "duration must be > 0");
        require(amount > 0, "amount must be > 0");
        require(cliffDuration <= duration, "cliff exceeds duration");
        require(
            token.balanceOf(address(this)) >= _totalVestingAmount() + amount,
            "insufficient token balance"
        );

        scheduleId = computeVestingScheduleId(beneficiary, holdersVestingCount[beneficiary]);
        holdersVestingCount[beneficiary] += 1;

        vestingSchedules[scheduleId] = VestingSchedule({
            beneficiary: beneficiary,
            cliff: start + cliffDuration,
            start: start,
            duration: duration,
            amountTotal: amount,
            released: 0,
            revocable: revocable,
            revoked: false
        });

        emit VestingScheduleCreated(scheduleId, beneficiary, amount);
    }

    /// @notice Release vested tokens to the beneficiary
    function release(bytes32 scheduleId) external {
        VestingSchedule storage schedule = vestingSchedules[scheduleId];
        require(
            msg.sender == schedule.beneficiary || msg.sender == owner,
            "not beneficiary or owner"
        );
        require(!schedule.revoked, "schedule revoked");

        uint256 releasable = _computeReleasableAmount(schedule);
        require(releasable > 0, "nothing to release");

        schedule.released += releasable;
        require(token.transfer(schedule.beneficiary, releasable), "transfer failed");

        emit TokensReleased(scheduleId, schedule.beneficiary, releasable);
    }

    /// @notice Revoke a vesting schedule, returning unvested tokens to owner
    function revoke(bytes32 scheduleId) external onlyOwner {
        VestingSchedule storage schedule = vestingSchedules[scheduleId];
        require(schedule.revocable, "not revocable");
        require(!schedule.revoked, "already revoked");

        uint256 releasable = _computeReleasableAmount(schedule);
        if (releasable > 0) {
            schedule.released += releasable;
            require(token.transfer(schedule.beneficiary, releasable), "transfer failed");
            emit TokensReleased(scheduleId, schedule.beneficiary, releasable);
        }

        uint256 refund = schedule.amountTotal - schedule.released;
        schedule.revoked = true;

        if (refund > 0) {
            require(token.transfer(owner, refund), "refund failed");
        }

        emit VestingRevoked(scheduleId, schedule.beneficiary, refund);
    }

    /// @notice Compute releasable amount for a schedule
    function computeReleasableAmount(bytes32 scheduleId) external view returns (uint256) {
        VestingSchedule storage schedule = vestingSchedules[scheduleId];
        return _computeReleasableAmount(schedule);
    }

    /// @notice Get vesting schedule details
    function getVestingSchedule(bytes32 scheduleId) external view returns (VestingSchedule memory) {
        return vestingSchedules[scheduleId];
    }

    /// @notice Compute schedule ID for a beneficiary and index
    function computeVestingScheduleId(address beneficiary, uint256 index) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(beneficiary, index));
    }

    // ---- internal ----

    function _computeReleasableAmount(VestingSchedule storage schedule) internal view returns (uint256) {
        if (schedule.revoked) return 0;
        if (block.timestamp < schedule.cliff) return 0;

        uint256 elapsed = block.timestamp - schedule.start;
        uint256 vested;
        if (elapsed >= schedule.duration) {
            vested = schedule.amountTotal;
        } else {
            vested = (schedule.amountTotal * elapsed) / schedule.duration;
        }
        return vested - schedule.released;
    }

    function _totalVestingAmount() internal view returns (uint256 total) {
        // NOTE: for production use, track this with a state variable
        // For simplicity, this is left as 0 here — integrate with holdersVestingCount
        return 0;
    }
}
