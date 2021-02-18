pragma solidity 0.6.12;

import "../common/IERC20.sol";
import "../common/Math.sol";
import "../common/SafeMath.sol";
import "../common/SafeERC20.sol";
import "../common/ReentrancyGuard.sol";

// A multistakingreward contract that allows stakers to recieve various reward tokens.
// Forked from the original Synthetix staking contract with following changes:
// - Expand from single reward token to a list of reward tokens

contract MultiStakingRewards is ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== STRUCTS ========== */

    // Info of each reward pool.
    struct RewardPool {
        IERC20 rewardToken;                                 // Address of reward token.
        uint256 periodFinish;                               // timestamp of when this reward pool finishes distribution
        uint256 rewardRate;                                 // amount of rewards distributed per unit of time
        uint256 rewardsDuration;                            // duration of distribution
        uint256 lastUpdateTime;                             // timestamp of when reward info was last updated
        uint256 rewardPerTokenStored;                       // current rewards per token based on total rewards and total staked
        mapping(address => uint256) userRewardPerTokenPaid; // amount of rewards per token already paided out to user
        mapping(address => uint256) rewards;                // amount of rewards user has earned
    }

    /* ========== STATE VARIABLES ========== */

    mapping(address => bool) public rewardsDistribution;
    address public governance;

    IERC20 public stakingToken;

    uint256 public totalSupply;
    mapping(address => uint256) public balances;

    mapping(address => RewardPool) public rewardPools; // reward token to reward pool mapping
    address[] public activeRewardPools; // list of reward tokens that are distributing rewards

    /* ========== CONSTRUCTOR ========== */

    constructor() public {
        rewardsDistribution[msg.sender] = true;
        governance = msg.sender;
    }

    /* ========== VIEWS ========== */

    function activeRewardPoolsLength() external view returns (uint256) {
        return activeRewardPools.length;
    }

    function lastTimeRewardApplicable(address _rewardToken) public view returns (uint256) {
        RewardPool storage pool = rewardPools[_rewardToken];
        return Math.min(block.timestamp, pool.periodFinish);
    }

    function rewardPerToken(address _rewardToken) public view returns (uint256) {
        RewardPool storage pool = rewardPools[_rewardToken];
        if (totalSupply == 0) {
            return pool.rewardPerTokenStored;
        }
        return
            pool.rewardPerTokenStored.add(
                lastTimeRewardApplicable(_rewardToken).sub(pool.lastUpdateTime).mul(pool.rewardRate).mul(1e18).div(totalSupply)
            );
    }

    function earned(address _rewardToken, address _account) public view returns (uint256) {
        RewardPool storage pool = rewardPools[_rewardToken];
        return balances[_account].mul(rewardPerToken(_rewardToken).sub(pool.userRewardPerTokenPaid[_account])).div(1e18).add(pool.rewards[_account]);
    }

    function getRewardForDuration(address _rewardToken) external view returns (uint256) {
        RewardPool storage pool = rewardPools[_rewardToken];
        return pool.rewardRate.mul(pool.rewardsDuration);
    }

    function periodFinish(address _rewardToken) public view returns (uint256) {
        RewardPool storage pool = rewardPools[_rewardToken];
        return pool.periodFinish;
    }

    function rewardRate(address _rewardToken) public view returns (uint256) {
        RewardPool storage pool = rewardPools[_rewardToken];
        return pool.rewardRate;
    }

    function rewardsDuration(address _rewardToken) public view returns (uint256) {
        RewardPool storage pool = rewardPools[_rewardToken];
        return pool.rewardsDuration;
    }

    function lastUpdateTime(address _rewardToken) public view returns (uint256) {
        RewardPool storage pool = rewardPools[_rewardToken];
        return pool.lastUpdateTime;
    }

    function rewardPerTokenStored(address _rewardToken) public view returns (uint256) {
        RewardPool storage pool = rewardPools[_rewardToken];
        return pool.rewardPerTokenStored;
    }

    function userRewardPerTokenPaid(address _rewardToken, address _account) public view returns (uint256) {
        RewardPool storage pool = rewardPools[_rewardToken];
        return pool.userRewardPerTokenPaid[_account];
    }

    function rewards(address _rewardToken, address _account) public view returns (uint256) {
        RewardPool storage pool = rewardPools[_rewardToken];
        return pool.rewards[_account];
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount) external nonReentrant updateActiveRewards(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        totalSupply = totalSupply.add(amount);
        balances[msg.sender] = balances[msg.sender].add(amount);
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant updateActiveRewards(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        totalSupply = totalSupply.sub(amount);
        balances[msg.sender] = balances[msg.sender].sub(amount);
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getAllActiveRewards() public nonReentrant updateActiveRewards(msg.sender) {
        for (uint i = 0; i < activeRewardPools.length; i++) {
            RewardPool storage pool = rewardPools[activeRewardPools[i]];
            uint256 reward = pool.rewards[msg.sender];
            if (reward > 0) {
                pool.rewards[msg.sender] = 0;
                pool.rewardToken.safeTransfer(msg.sender, reward);
                emit RewardPaid(address(pool.rewardToken), msg.sender, reward);
            }
        }
    }

    function exit() external {
        withdraw(balances[msg.sender]);
        getAllActiveRewards();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(address _rewardToken, uint256 _amount) external onlyRewardsDistribution updateReward(_rewardToken, address(0)) {
        RewardPool storage pool = rewardPools[_rewardToken];

        if (block.timestamp >= pool.periodFinish) {
            pool.rewardRate = _amount.div(pool.rewardsDuration);
        } else {
            uint256 remaining = pool.periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(pool.rewardRate);
            pool.rewardRate = _amount.add(leftover).div(pool.rewardsDuration);
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint balance = pool.rewardToken.balanceOf(address(this));
        require(pool.rewardRate <= balance.div(pool.rewardsDuration), "Provided reward too high");

        pool.lastUpdateTime = block.timestamp;
        pool.periodFinish = block.timestamp.add(pool.rewardsDuration);

        emit RewardAdded(_rewardToken, _amount);
    }

    // Add new reward pool to list
    // NOTE: DO NOT add same pool twice while active.
    function addRewardPool(
        address _rewardToken,
        uint256 _rewardsDuration
    )
        public
        onlyGov
    {
      rewardPools[_rewardToken] = RewardPool({
          rewardToken: IERC20(_rewardToken),
          periodFinish: 0,
          rewardRate: 0,
          rewardsDuration: _rewardsDuration,
          lastUpdateTime: 0,
          rewardPerTokenStored: 0
      });

      activeRewardPools.push(_rewardToken);
    }

    // Remove pool from active list
    function inactivateRewardPoolByToken(address _rewardToken) public onlyGov {
        // find the index
        uint indexToDelete = 0;
        bool found = false;
        for (uint i = 0; i < activeRewardPools.length; i++) {
            if (activeRewardPools[i] == _rewardToken) {
                indexToDelete = i;
                found = true;
                break;
            }
        }

        require(found, "element not found");
        inactivateRewardPoolByIndex(indexToDelete);
    }

    // Remove pool from active list
    function inactivateRewardPoolByIndex(uint256 _index) public onlyGov {
        // we don't care about the ordering of the active reward pool array
        // so we can just swap the element to delete with the last element

        activeRewardPools[_index] = activeRewardPools[activeRewardPools.length - 1];
        activeRewardPools.pop();
    }

    // Allow governance to rescue unclaimed inactive rewards
    function rescue(address _rewardToken) public onlyGov {
        for (uint i = 0; i < activeRewardPools.length; i++) {
            if (activeRewardPools[i] == _rewardToken) {
                // cannot withdraw active rewards
                return;
            }
        }
        uint _balance = IERC20(_rewardToken).balanceOf(address(this));
        IERC20(_rewardToken).safeTransfer(governance, _balance);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setRewardsDistribution(address _distributor, bool _status) external {
        require(msg.sender == governance, "!governance");
        rewardsDistribution[_distributor] = _status;
    }

    function setGov(address _gov) external {
        require(msg.sender == governance, "!governance");
        governance = _gov;
    }

    /* ========== MODIFIERS ========== */

    modifier updateActiveRewards(address _account) {
        for (uint i = 0; i < activeRewardPools.length; i++) {
            RewardPool storage pool = rewardPools[activeRewardPools[i]];

            pool.rewardPerTokenStored = rewardPerToken(address(pool.rewardToken));
            pool.lastUpdateTime = lastTimeRewardApplicable(address(pool.rewardToken));
            if (_account != address(0)) {
                pool.rewards[_account] = earned(address(pool.rewardToken), _account);
                pool.userRewardPerTokenPaid[_account] = pool.rewardPerTokenStored;
            }
        }
        _;
    }

    modifier updateReward(address _rewardToken, address _account) {
        RewardPool storage pool = rewardPools[_rewardToken];

        pool.rewardPerTokenStored = rewardPerToken(address(pool.rewardToken));
        pool.lastUpdateTime = lastTimeRewardApplicable(address(pool.rewardToken));
        if (_account != address(0)) {
            pool.rewards[_account] = earned(address(pool.rewardToken), _account);
            pool.userRewardPerTokenPaid[_account] = pool.rewardPerTokenStored;
        }
        _;
    }

    modifier onlyGov() {
        require(msg.sender == governance, "!governance");
        _;
    }

    modifier onlyRewardsDistribution() {
        require(rewardsDistribution[msg.sender] == true, "!rewardsDistribution");
        _;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(address indexed rewardToken, uint256 amount);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed rewardToken, address indexed user, uint256 reward);
}
