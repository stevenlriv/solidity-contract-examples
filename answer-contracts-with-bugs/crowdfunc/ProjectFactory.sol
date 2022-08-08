// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import { Project } from "./Project.sol";

contract ProjectFactory {
  Project[] public projects;

  event ProjectCreated(
    address indexed creator,
    address campaign
  );

  function createProject(uint256 _goal) external returns (address) {
      Project campaign = new Project(msg.sender, _goal);
      projects.push(campaign);
      emit ProjectCreated(msg.sender, address(campaign));
      return address(campaign);
  }

  function getProjects() external view returns (Project[] memory) {
    return projects;
  }
}
