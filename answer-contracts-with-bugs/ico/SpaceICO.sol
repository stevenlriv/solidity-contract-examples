//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./SpaceCoin.sol";

import "hardhat/console.sol";

contract SpaceICO {

    /// @notice The ratio at which contributors can redeem their invested ETH for
    uint256 public constant ICO_EXCHANGE_RATE = 5;

    /// @notice The total ETH contribution limit in the first Phase
    uint256 public constant SEED_LIMIT = 15000 ether;
    /// @notice The total ETH contribution limit in the second and third Phases
    uint256 public constant GENERAL_LIMIT = 30000 ether;

    /// @notice The individual ETH contribution limit in the first Phase
    uint256 public constant SEED_INDV_LIMIT = 1500 ether;
    /// @notice The individual ETH contribution limit in the second Phase
    uint256 public constant GENERAL_INDV_LIMIT = 1000 ether;

    /// @notice Address of the SPC token
    SpaceCoin private spaceCoin;

    /// @notice Address that is able to pause contributing
    address public owner;

    /// @notice Address that recieves the contributed ETH funds once
    /// the Open phase is reached
    address public treasury;

    /// @notice true if contributing is paused, false otherwise
    bool public paused;

    /// @notice The current phase of the iCO
    Phase public phase;

    /// @notice Sum total of all ETH every contributed
    uint256 public totalContributed;

    /// @notice Individual contributor  ETH contribution amounts
    mapping(address => uint256) public contributions;

    /// @notice Amounts of ETH that have been redeemed per contributor
    mapping(address => uint256) public contributionsRedeemed;

    /// @notice Keeps track of who is able to contribute in Phase Seed
    mapping(address => bool) public isSeedInvestor;

    enum Phase {
        Seed,
        General,
        Open
    }

    event PhaseChange(Phase phase);
    event Contribute(
        address indexed contributor,
        Phase indexed phase,
        uint256 eth
    );
    event Redeem(address indexed contributor, uint256 tokens);

    error NotOwner(address owner);
    error InvalidPhase(Phase currentPhase, Phase expectedCurrentPhase);
    error Paused();
    error Unauthorized();
    error ContributionOverLimit(uint256 available);
    error NoFunds();

    constructor(
        address _owner,
        SpaceCoin _spaceCoin,
        address _treasury
    ) {
        owner = _owner;
        treasury = _treasury;
        spaceCoin = _spaceCoin;
    }

    /// @dev Authorize certain functions to only be executed by the owner
    modifier onlyOwner() {
        // gas savings
        address _owner = owner;
        if (msg.sender != _owner) revert NotOwner(_owner);
        _;
    }

    /// @notice Turn on and off the ability to pause calling `SpaceICO.contribute`
    /// @param pause true if contributing should be paused, false otherwise
    function togglePause(bool pause) external onlyOwner {
        paused = pause;
    }

    /// @notice Add multiple addresses as seed investors
    /// @param addresses The new addresses to add
    function toggleSeedInvestors(address[] calldata addresses, bool toggle)
        external
    {
        for (uint256 i = 0; i < addresses.length; i++) {
            isSeedInvestor[addresses[i]] = toggle;
        }
    }

    /// @notice Calculate the amount that can be contributed based
    /// on which phase the ICO is in
    function fundingCapacity() public view returns (uint256) {
        if (phase == Phase.Seed) {
            return SEED_LIMIT - totalContributed;
        }
        if (phase == Phase.General) {
            return GENERAL_LIMIT - totalContributed;
        }

        // ASSUMPTION: SpaceCoin decimals are the same as ETH (10^18)

        // decrease funding capacity as more SPC is claimed in the OPEN phase
        return
            (spaceCoin.balanceOf(address(this)) / ICO_EXCHANGE_RATE) -
            totalContributed;
    }

    /// @notice Calculate the amount that can be contributed based
    /// on which phase the ICO is in and how much the user has contributed
    /// @dev The limits are not additive; so it's possible to contribute 1_500
    /// ETH in Phase Seed, and then not be able to contribute anything in Phase General
    /// @param user The address to check the contribution limit for
    function availableToContribute(address user) public view returns (uint256) {
        uint256 spent = contributions[user];
        uint256 available = fundingCapacity();

        if (phase == Phase.Seed) {
            if (!isSeedInvestor[msg.sender]) {
                return 0;
            }
            uint256 limit = min(available, SEED_INDV_LIMIT);
            return limit - spent;
        }
        if (phase == Phase.General) {
            uint256 limit = min(available, GENERAL_INDV_LIMIT);
            return limit - spent;
        }

        return available;
    }

    /// @notice Move the current phase to the next phase
    function transitionToNextPhase(Phase expectedCurrent) external {
        if (phase != expectedCurrent)
            revert InvalidPhase(phase, expectedCurrent);
        phase = Phase(uint8(expectedCurrent) + 1);
    }

    /// @notice Invest ETH in the ICO, so that in the Phase Open the msg.sender may
    /// redeem their ETH for 5x the amount of SPC
    /// @dev If the current phase is Open, then we save them a transaction by automatically
    /// calling `SpaceICO.redeem`
    function contribute() external payable {
        if (paused) revert Paused();

        if (phase == Phase.Seed) {
            if (!isSeedInvestor[msg.sender]) revert Unauthorized();
        }

        uint256 available = availableToContribute(msg.sender);
        uint256 _available = available;

        if (msg.value > _available) revert ContributionOverLimit(_available);

        totalContributed += msg.value;
        contributions[msg.sender] += msg.value;
        if (phase == Phase.Open) {
            redeem();
        }
    }

    /// @notice Allows the msg.sender to withdraw an amount of SPC according to
    /// how much ETH they had previously contributed
    function redeem() public {
        if (phase != Phase.Open) revert Unauthorized();
        if (contributions[msg.sender] == 0) revert NoFunds();

        // ASSUMPTION: SpaceCoin decimals are the same as ETH (10^18)
        uint256 owed = contributions[msg.sender] * ICO_EXCHANGE_RATE;
        spaceCoin.transfer(msg.sender, owed);
        contributions[msg.sender] = 0;
    }

    // In a future project...
    // function withdraw(address to) external {
    //   require(msg.sender == treasury, "UNAUTHORIZED");
    //   (bool success, ) = to.call{ value: address(this).balance }("");
    //   require(success, "WITHDRAW_FAILED");
    // }

    /// @notice Helper function calculate the minimum of two values
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
