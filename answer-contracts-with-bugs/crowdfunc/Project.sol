// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";


contract Project is ERC721 {
  uint256 constant MIN_CONTRIBUTION = 0.01 ether;   // no slot!

  uint256 public goal;                              // slot 0
  uint256 public totalRaised;                       // slot 1
  uint256 public currentFunds;                      // slot 2

  uint256 public badgeIdCounter = 1;                // slot 3

  address public creator;                           // slot 4
  uint48 public deadline;                           // slot 4
  bool cancelled;                                   // slot 4

  mapping(address => uint256) public contributions; // slot 5

  enum Status {
    ACTIVE,
    FUNDED,
    FAILED
  }

  constructor(address _creator, uint256 _goal) ERC721("Project Contribution Badge", "CCB") {
    goal = _goal;
    creator = _creator;
    deadline = uint48(block.timestamp) + 30 days;
  }

  modifier onlyCreator() {
    if (msg.sender != creator) revert MustBeCreator(creator, msg.sender);
    _;
  }

  function status() public view returns (Status) {
    if (totalRaised >= goal) {
      return Status.FUNDED;
    }
    else if (cancelled || block.timestamp >= deadline) {
      return Status.FAILED;
    }
    else {
      return Status.ACTIVE;
    }
  }

  function contribute() external payable {

    if (status() != Status.ACTIVE) revert MustBeActiveState();
    if (msg.value < MIN_CONTRIBUTION) revert ContributionUnderMinAmount(msg.value);

    contributions[msg.sender] += msg.value;

    if (contributions[msg.sender] >= 1 ether) {
      _mint(msg.sender, badgeIdCounter++);
    }

    totalRaised += msg.value;
    currentFunds += msg.value;

    emit Contribute(msg.sender, msg.value);
  }

  function withdraw(uint256 _amount, address to) external onlyCreator {
    if (status() != Status.FUNDED) revert MustBeFundedState();
    if (_amount > currentFunds) revert InsufficientFunds(_amount, currentFunds);

    currentFunds -= _amount;

    (bool success, ) = to.call{value: _amount}("");
    require(success, "Withdraw failed.");
    emit Withdraw(to, _amount);
  }

  function refund() external {
    if (status() != Status.FAILED) revert MustBeFailedState();
    if (contributions[msg.sender] == 0) revert MustHaveNonZeroContributions();

    uint256 amount = contributions[msg.sender];

    (bool success, ) = msg.sender.call{value: amount}("");
    require(success, "Refund failed.");

    currentFunds -= amount;
    contributions[msg.sender] = 0;

    emit Refund(msg.sender, amount);
  }

  function cancel() external onlyCreator {
    if (status() != Status.ACTIVE) revert MustBeActiveState();
    cancelled = true;
    emit Cancel();
  }

  event Contribute(address indexed contributor, uint256 amount);
  event Withdraw(address indexed to, uint256 amount);
  event Refund(address indexed contributor, uint256 amount);
  event Cancel();


  error MustBeCreator(address creatorAddress, address msgSender);
  error MustBeActiveState();
  error MustBeFundedState();
  error MustBeFailedState();
  error ContributionUnderMinAmount(uint256 amount);
  error InsufficientFunds(uint256 amount, uint256 currentFunds);
  error MustHaveNonZeroContributions();
}
