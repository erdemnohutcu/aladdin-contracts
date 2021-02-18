pragma solidity 0.6.12;

import "../common/IERC20.sol";
import "../common/SafeERC20.sol";

interface IRewardsDistributionRecipient {
    function notifyRewardAmount(address _rewardToken, uint256 reward) external;
}

// RewardsDistributor allows Fund Managers to send rewards
contract RewardsDistributor {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    address public governance;
    mapping(address => bool) public fundManager;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address[] memory _fundManagers
    )
        public
    {
        governance = msg.sender;

        for(uint256 i = 0; i < _fundManagers.length; i++) {
            fundManager[_fundManagers[i]] = true;
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function addFundManager(address _address)
        external
        onlyGov
    {
        fundManager[_address] = true;
    }

    function removeFundManager(address _address)
        external
        onlyGov
    {
        fundManager[_address] = false;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function distributeRewards(
        IRewardsDistributionRecipient[] calldata _recipients,
        IERC20[] calldata _rewardTokens,
        uint256[] calldata _amounts
    )
        external
        onlyFundManager
    {
        uint256 len = _recipients.length;
        require(len > 0, "Must choose recipients");
        require(len == _rewardTokens.length, "Mismatching inputs");
        require(len == _amounts.length, "Mismatching inputs");

        for(uint i = 0; i < len; i++){
            uint256 amount = _amounts[i];
            IERC20 rewardToken = _rewardTokens[i];
            IRewardsDistributionRecipient recipient = _recipients[i];
            // Send the RewardToken to recipient
            rewardToken.safeTransferFrom(msg.sender, address(recipient), amount);
            // Only after successfull tx - notify the contract of the new funds
            recipient.notifyRewardAmount(address(rewardToken), amount);

            emit DistributedReward(msg.sender, address(recipient), address(rewardToken), amount);
        }
    }

    /* ========== MODIFIERS ========== */

    modifier onlyGov() {
        require(msg.sender == governance, "!governance");
        _;
    }

    modifier onlyFundManager() {
        require(fundManager[msg.sender] == true, "!manager");
        _;
    }

    /* ========== EVENTS ========== */

    event DistributedReward(address funder, address recipient, address rewardToken, uint256 amount);
}
