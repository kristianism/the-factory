// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.36;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {CommonErrors} from "@common/CommonErrors.sol";
import {CommonEvents} from "@common/CommonEvents.sol";

contract StandardYieldFarm is Initializable, Ownable2StepUpgradeable, ReentrancyGuard, CommonErrors, CommonEvents {
    using SafeERC20 for IERC20;

    error UnsupportedToken();
    error InvalidPoolParameters();
    uint256 public constant MAX_POOLS = 50;
    /// @notice Accounted principal; direct donations do not dilute rewards.
    mapping(uint256 => uint256) public totalStaked;
    /// @notice Earned rewards still owed after a funding shortfall.
    mapping(uint256 => mapping(address => uint256)) public unpaidRewards;
    event RewardPaid(address indexed user, uint256 indexed pid, uint256 paid, uint256 unpaid);

    /// @notice Emitted when a user deposits into a yield farm.
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    /// @notice Emitted when a user withdraws from a yield farm.
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    /// @notice Emitted when a user emergency withdraws from a yield farm.
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    /// @notice Emitted when the fee address is set.
    event SetFeeAddress(address indexed user, address indexed newAddress);
    /// @notice Emitted when the dev address is set.
    event SetDevAddress(address indexed user, address indexed newAddress);
    /// @notice Emitted when the emission rate is updated.
    event UpdateEmissionRate(address indexed user, uint256 rewardPerSecond);

    // Info of each user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;
        uint256 allocPoint;
        uint256 lastRewardSecond;
        uint256 accRewardPerShare;
        uint256 depositFeeBP;
    }

    // The reward token
    IERC20 public rewardToken;
    // Dev address.
    address public devAddress;
    // reward tokens created/distributed per block.
    uint256 public rewardPerSecond;
    // Bonus muliplier for early makers.
    uint256 public constant BONUS_MULTIPLIER = 1;
    // Deposit Fee address
    address public feeAddress;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when reward mining starts.
    uint256 public startTimestamp;

    /// @notice Disables the ability to call the initializer
    constructor() {
        _disableInitializers();
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IERC20 => bool) public poolExistence;
    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    function initialize(
        IERC20 _rewardToken,
        address _devAddress,
        address _feeAddress,
        uint256 _rewardPerSecond,
        uint256 _startTimestamp
    ) external initializer {
        if (address(_rewardToken).code.length == 0) revert UnsupportedToken();
        if (_feeAddress == address(0) || _feeAddress == address(this) || _devAddress == address(0)) {
            revert ZeroAddress();
        }
        if (_rewardPerSecond > type(uint128).max || _startTimestamp < block.timestamp) revert InvalidPoolParameters();
        __Ownable2Step_init();
        __Ownable_init(_devAddress);

        rewardToken = _rewardToken;
        devAddress = _devAddress;
        feeAddress = _feeAddress;
        rewardPerSecond = _rewardPerSecond;
        startTimestamp = _startTimestamp;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        uint256 _depositFeeBP,
        bool /* retained for ABI compatibility; pools are always checkpointed */
    )
        public
        onlyOwner
        nonReentrant
        nonDuplicated(_lpToken)
    {
        require(_depositFeeBP <= 10000, "add: invalid deposit fee basis points");
        if (address(_lpToken).code.length == 0 || _lpToken == rewardToken) revert UnsupportedToken();
        if (_allocPoint > type(uint64).max || poolInfo.length >= MAX_POOLS) revert InvalidPoolParameters();

        _massUpdatePools();

        uint256 lastRewardSecond = block.timestamp > startTimestamp ? block.timestamp : startTimestamp;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolExistence[_lpToken] = true;
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardSecond: lastRewardSecond,
                accRewardPerShare: 0,
                depositFeeBP: _depositFeeBP
            })
        );
    }

    // Update the given pool's reward allocation point and deposit fee. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint16 _depositFeeBP,
        bool /* always checkpoint */
    )
        public
        onlyOwner
        nonReentrant
    {
        require(_depositFeeBP <= 10000, "set: invalid deposit fee basis points");
        if (_allocPoint > type(uint64).max) revert InvalidPoolParameters();

        _massUpdatePools();

        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
    }

    // Return reward multiplier over the given _from to _to second.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return (_to - _from) * BONUS_MULTIPLIER;
    }

    // View function to see pending rewards on frontend.
    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply = totalStaked[_pid];

        if (block.timestamp > pool.lastRewardSecond && lpSupply != 0 && totalAllocPoint != 0 && pool.allocPoint != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardSecond, block.timestamp);
            uint256 reward = Math.mulDiv(multiplier * rewardPerSecond, pool.allocPoint, totalAllocPoint);
            accRewardPerShare = accRewardPerShare + Math.mulDiv(reward, 1e18, lpSupply);
        }

        return Math.mulDiv(user.amount, accRewardPerShare, 1e18) - user.rewardDebt + unpaidRewards[_pid][_user];
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public nonReentrant {
        _massUpdatePools();
    }

    function _massUpdatePools() internal {
        uint256 length = poolInfo.length;

        for (uint256 pid = 0; pid < length; ++pid) {
            _updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public nonReentrant {
        _updatePool(_pid);
    }

    function _updatePool(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];

        if (block.timestamp <= pool.lastRewardSecond) {
            return;
        }

        uint256 lpSupply = totalStaked[_pid];

        if (lpSupply == 0 || pool.allocPoint == 0 || totalAllocPoint == 0) {
            pool.lastRewardSecond = block.timestamp;
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardSecond, block.timestamp);
        uint256 reward = Math.mulDiv(multiplier * rewardPerSecond, pool.allocPoint, totalAllocPoint);

        // For a generic reward token we do NOT mint here;
        // the contract is expected to be funded with rewardToken tokens beforehand.
        pool.accRewardPerShare = pool.accRewardPerShare + Math.mulDiv(reward, 1e18, lpSupply);
        pool.lastRewardSecond = block.timestamp;
    }

    // Deposit staking tokens for reward allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        _updatePool(_pid);

        _payRewards(_pid, msg.sender);

        uint256 credited;
        if (_amount > 0) {
            uint256 beforeBalance = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            // Keep the default template predictable: taxed and rebasing assets are unsupported.
            if (pool.lpToken.balanceOf(address(this)) - beforeBalance != _amount) revert UnsupportedToken();
            uint256 depositFee = Math.mulDiv(_amount, pool.depositFeeBP, 10_000);
            credited = _amount - depositFee;
            if (depositFee > 0) pool.lpToken.safeTransfer(feeAddress, depositFee);
            if (pool.lpToken.balanceOf(address(this)) != beforeBalance + credited) revert UnsupportedToken();
            user.amount += credited;
            totalStaked[_pid] += credited;
        }

        user.rewardDebt = Math.mulDiv(user.amount, pool.accRewardPerShare, 1e18);
        emit Deposit(msg.sender, _pid, credited);
    }

    // Withdraw LP tokens from the yield farm.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "Withdrawal exceeds stake");
        _updatePool(_pid);
        _payRewards(_pid, msg.sender);

        if (_amount > 0) {
            user.amount = user.amount - _amount;
            totalStaked[_pid] -= _amount;
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }

        user.rewardDebt = Math.mulDiv(user.amount, pool.accRewardPerShare, 1e18);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        _updatePool(_pid);
        uint256 amount = user.amount;
        totalStaked[_pid] -= amount;
        unpaidRewards[_pid][msg.sender] = 0;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Preserve shortfalls instead of silently deleting the user's earned rewards.
    function _payRewards(uint256 pid, address account) internal {
        UserInfo storage user = userInfo[pid][account];
        uint256 accrued = Math.mulDiv(user.amount, poolInfo[pid].accRewardPerShare, 1e18);
        uint256 owed = accrued - user.rewardDebt + unpaidRewards[pid][account];
        uint256 paid = Math.min(owed, rewardToken.balanceOf(address(this)));
        user.rewardDebt = accrued;
        unpaidRewards[pid][account] = owed - paid;
        if (paid > 0) rewardToken.safeTransfer(account, paid);
        if (owed > 0) emit RewardPaid(account, pid, paid, owed - paid);
    }

    function setDevAddress(address _devAddress) public nonReentrant {
        if (_devAddress == address(0)) revert ZeroAddress();
        require(msg.sender == devAddress, "Caller is not developer");
        devAddress = _devAddress;
        emit SetDevAddress(msg.sender, _devAddress);
    }

    function setFeeAddress(address _feeAddress) public nonReentrant {
        if (_feeAddress == address(0) || _feeAddress == address(this)) revert InvalidAddress();
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    function updateEmissionRate(uint256 _rewardPerSecond) public onlyOwner nonReentrant {
        if (_rewardPerSecond > type(uint128).max) revert InvalidPoolParameters();
        _massUpdatePools();
        rewardPerSecond = _rewardPerSecond;
        emit UpdateEmissionRate(msg.sender, _rewardPerSecond);
    }
}
