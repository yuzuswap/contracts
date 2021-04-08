pragma solidity 0.6.12;


import './libs/IBEP20.sol';
import './libs/SafeBEP20.sol';
import "@openzeppelin/contracts/access/Ownable.sol";
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

contract CitrusBar is Ownable , ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. Rewards to distribute per block.
        uint256 lastRewardBlock;  // Last block number that Rewards distribution occurs.
        uint256 accRewardPerShare; // Accumulated Rewards per share, times 1e12. See below.
    }

    // The SALT TOKEN!
    IBEP20 public syrup;
    IBEP20 public rewardToken;

    // Reward tokens created per block.
    uint256 public rewardPerBlock;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (address => UserInfo) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 private totalAllocPoint = 0;
    // The block number when Reward mining starts.
    uint256 public startBlock;
    // The block number when Reward mining ends.
    uint256 public bonusEndBlock;

    uint256 public burnMultiplier;
    address public burnAddress = address(0xdead);


    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Burn(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event EmergencyRewardWithdraw( uint256 amount);
    event StopRewards(uint blockNumber);

    constructor(
        IBEP20 _syrup,
        IBEP20 _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock,
        uint256 _burnMultiplier
    ) public {
        syrup = _syrup;
        rewardToken = _rewardToken;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;
        burnMultiplier = _burnMultiplier;

        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: _syrup,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accRewardPerShare: 0
        }));

        totalAllocPoint = 1000;

    }

    function stopReward() external onlyOwner {
        bonusEndBlock = block.number;

        emit StopRewards(bonusEndBlock);
    }

    function adjustBlockEnd() public onlyOwner {
        uint256 totalLeft = rewardToken.balanceOf(address(this));
        bonusEndBlock = block.number + totalLeft.div(rewardPerBlock);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from);
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock.sub(_from);
        }
    }

    // View function to see pending Reward on frontend.
    function pendingReward(address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 cakeReward = multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accRewardPerShare = accRewardPerShare.add(cakeReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 cakeReward = multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        pool.accRewardPerShare = pool.accRewardPerShare.add(cakeReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() external {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }


    // Stake SYRUP tokens to SmartChef
    function deposit(uint256 _amount) external nonReentrant{
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];

        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accRewardPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);
                rewardToken.safeTransfer(address(msg.sender), pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);

        emit Deposit(msg.sender, _amount);
    }

    // Withdraw SYRUP tokens from STAKING.
    function withdraw(uint256 _amount) external nonReentrant{
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accRewardPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            rewardToken.safeTransfer(address(msg.sender), pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);

            if(burnMultiplier>0)
            {
                uint256 burnAmount = _amount.mul(burnMultiplier).div(1000);
                _amount = _amount.sub(burnAmount);
                pool.lpToken.safeTransfer(burnAddress, burnAmount);

                emit Burn(burnAddress, burnAmount);
            }

            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);

        emit Withdraw(msg.sender, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() external nonReentrant{
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        uint256 _amount = user.amount;

           if(burnMultiplier>0)
            {
                uint256 burnAmount = _amount.mul(burnMultiplier).div(1000);
                _amount = _amount.sub(burnAmount);
                pool.lpToken.safeTransfer(burnAddress, burnAmount);

                emit Burn(burnAddress, burnAmount);
            }



        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        user.amount = 0;
        user.rewardDebt = 0;
        emit EmergencyWithdraw(msg.sender,_amount);
    }

    // Withdraw reward. EMERGENCY ONLY.
    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        require(_amount < rewardToken.balanceOf(address(this)), 'not enough token');
        rewardToken.safeTransfer(address(msg.sender), _amount);

        emit EmergencyRewardWithdraw(_amount);
    }

}

