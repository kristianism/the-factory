// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {CommonErrors} from "@common/CommonErrors.sol";
import {CommonEvents} from "@common/CommonEvents.sol";

contract StandardYieldFarm is 
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    CommonErrors,
    CommonEvents
{
    using SafeERC20 for IERC20;

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
        __Ownable_init(_devAddress);
        __ReentrancyGuard_init();

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
        bool _withUpdate
    ) 
        public
        onlyOwner
        nonDuplicated(_lpToken)
    {
        require(_depositFeeBP <= 10000, "add: invalid deposit fee basis points");
        
        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 lastRewardSecond = block.timestamp > startTimestamp ? block.timestamp : startTimestamp;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardSecond : lastRewardSecond,
        accRewardPerShare : 0,
        depositFeeBP : _depositFeeBP
        }));
    }

    // Update the given pool's reward allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 10000, "set: invalid deposit fee basis points");
        
        if (_withUpdate) {
            massUpdatePools();
        }

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
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        
        if (block.timestamp > pool.lastRewardSecond && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardSecond, block.timestamp);
            uint256 reward = (multiplier * rewardPerSecond * pool.allocPoint) / totalAllocPoint;
            accRewardPerShare = accRewardPerShare + (reward * 1e18) / lpSupply;
        }

        return (user.amount * accRewardPerShare) / 1e18 - user.rewardDebt;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        
        if (block.timestamp <= pool.lastRewardSecond) {
            return;
        }

        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardSecond = block.timestamp;
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardSecond, block.timestamp);
        uint256 reward = (multiplier * rewardPerSecond * pool.allocPoint) / totalAllocPoint;

        // For a generic reward token we do NOT mint here;
        // the contract is expected to be funded with rewardToken tokens beforehand.
        pool.accRewardPerShare = pool.accRewardPerShare + (reward * 1e18) / lpSupply;
        pool.lastRewardSecond = block.timestamp;
    }

    // Deposit LP tokens to MasterChef for reward allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);

        if (user.amount > 0) {
            uint256 pending = (user.amount * pool.accRewardPerShare) / 1e18 - user.rewardDebt;
            if (pending > 0) {
                safeRewardTransfer(msg.sender, pending);
            }
        }

        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = (_amount * pool.depositFeeBP) / 10000;
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount + _amount - depositFee;
            } else {
                user.amount = user.amount + _amount;
            }
        }

        user.rewardDebt = (user.amount * pool.accRewardPerShare) / 1e18;
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from the yield farm.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = (user.amount * pool.accRewardPerShare) / 1e18 - user.rewardDebt;
        if (pending > 0) {
            safeRewardTransfer(msg.sender, pending);
        }

        if (_amount > 0) {
            user.amount = user.amount - _amount;
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }

        user.rewardDebt = (user.amount * pool.accRewardPerShare) / 1e18;
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe reward transfer function, just in case if rounding error causes pool to not have enough tokens.
    function safeRewardTransfer(address _to, uint256 _amount) internal {
        uint256 bal = rewardToken.balanceOf(address(this));
        bool transferSuccess = false;

        if (_amount > bal) {
            transferSuccess = rewardToken.transfer(_to, bal);
        } else {
            transferSuccess = rewardToken.transfer(_to, _amount);
        }

        require(transferSuccess, "safeRewardTransfer: transfer failed");
    }

    function setDevAddress(address _devAddress) public {
        require(msg.sender == devAddress, "dev: wut?");
        devAddress = _devAddress;
        emit SetDevAddress(msg.sender, _devAddress);
    }

    function setFeeAddress(address _feeAddress) public {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    function updateEmissionRate(uint256 _rewardPerSecond) public onlyOwner {
        massUpdatePools();
        rewardPerSecond = _rewardPerSecond;
        emit UpdateEmissionRate(msg.sender, _rewardPerSecond);
    }
}