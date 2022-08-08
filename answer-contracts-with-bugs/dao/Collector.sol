//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./interface/NftMarketplace.sol";
import "hardhat/console.sol";

contract Collector {
    uint256 public constant VOTE_TIME = 3 days;

    /// @dev default error message if a Proposal's function call reverts without
    /// an error of its own
    string private constant ERROR_MESSAGE = "Collector: call reverted without message";

    string public constant DAPP_NAME = "CollectorDAO";
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint8 support)");

    enum VoteType {
        No,
        Yes,
        Abstain
    }

    bool internal executing;

    address[] public members;
    mapping(address => bool) isMember;

    mapping(uint => Proposal) public proposals;

    struct Proposal {
        uint id;
        address proposer;

        bool canceled;
        bool executed;

        uint createdAt;

        uint noVotes;
        uint yesVotes;
        uint abstainVotes;
        mapping(address => bool) hasVoted;
    }

    event VoteCast(uint indexed proposalId, address indexed voter, VoteType support);
    event MemberJoined(address newMember);

    error MustBeMember();
    error MustPayOneEth(uint256 value);
    error VotingStillOngoing();
    error QuorumNotReached(uint256 total, uint256 quorum);
    error NonMember(address addr);
    error NoSuchProposal(uint256 proposalId);
    error HasAlreadyVoted(address addr);
    error InvalidSignature();
    error InvalidVLength(uint256 expected, uint256 actual);
    error InvalidRLength(uint256 expected, uint256 actual);
    error InvalidSLength(uint256 expected, uint256 actual);
    error MustBeCalledByCollector();
    error PriceTooHigh(uint256 price, uint256 maxPrice);
    error VotingHasEnded();

    modifier onlyMembers() {
        if (!isMember[msg.sender]) revert MustBeMember();
        _;
    }

    function join() external payable {
        if (msg.value < 1 ether) revert MustPayOneEth(msg.value);
        members.push(msg.sender);
        isMember[msg.sender] = true;

        emit MemberJoined(msg.sender);
    }

    function propose(
        address[] memory targets,
        uint[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public onlyMembers {
        uint proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        Proposal storage p = proposals[proposalId];
        p.id = proposalId;
        p.proposer = msg.sender;
        p.createdAt = block.timestamp;
    }

    function execute(
        address[] memory targets,
        uint[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public onlyMembers {
        uint proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        Proposal storage p = proposals[proposalId];

        // Validate time
        if (block.timestamp < p.createdAt + VOTE_TIME) revert VotingStillOngoing();

        // Validate quorum
        uint total = p.noVotes + p.yesVotes + p.abstainVotes;
        uint quorum = members.length * 25 / 100;
        if (total < quorum) revert QuorumNotReached(total, quorum);

        // Execute proposed function calls
        executing = true;

        for (uint256 i = 0; i < targets.length; ++i) {
            (bool success, bytes memory returndata) = targets[i].call{value: values[i]}(calldatas[i]);

            if (success) {
                // We good
            }
            else if (returndata.length > 0) {
                assembly {
                    // `returndata` consists of 2 parts:
                    //    1) the first 32 bytes contain the length of the return data (in bytes)
                    //    2) the actual return data, padded to 32 bytes with 0's
                    // So for instance, a returndata with the UTF8 string "abcd" would look like:
                    // 0x00: 0000000000000000000000000000000000000000000000000000000000000004
                    // 0x20: 6162636400000000000000000000000000000000000000000000000000000000

                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            }
            else {
                // No revert reason given
                revert(ERROR_MESSAGE);
            }
        }
        executing = false;
    }

    function vote(uint proposalId, VoteType support) external {
        _vote(msg.sender, proposalId, support);
    }

    function _vote(address voter, uint256 proposalId, VoteType support) internal {
        Proposal storage p = proposals[proposalId];

        if (!isMember[voter]) revert NonMember(voter);
        if (p.id == 0) revert NoSuchProposal(proposalId);
        if (p.hasVoted[voter]) revert HasAlreadyVoted(voter);
        if (block.timestamp >= p.createdAt + VOTE_TIME) revert VotingHasEnded();

        if (support == VoteType.No) {
            p.noVotes += 1;
        }
        else if (support == VoteType.Yes) {
            p.yesVotes += 1;
        }
        else {
            p.abstainVotes += 1;
        }
        p.hasVoted[voter] = true;

        emit VoteCast(proposalId, voter, support);
    }

    function voteBySig(uint proposalId, uint8 support, uint8 v, bytes32 r, bytes32 s) public {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(DAPP_NAME)), block.chainid, address(this)));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, support));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        if (signatory == address(0)) revert InvalidSignature();

        _vote(signatory, proposalId, VoteType(support));
    }

    function recordVotesBySigs(
        uint proposalId,
        uint8[] calldata support,
        uint8[] calldata vs,
        bytes32[] calldata rs,
        bytes32[] calldata ss
    ) external {
        if (support.length != vs.length) revert InvalidVLength(support.length, vs.length);
        if (support.length != rs.length) revert InvalidRLength(support.length, rs.length);
        if (support.length != ss.length) revert InvalidSLength(support.length, ss.length);

        for (uint i = 0; i < support.length; i++) {
            voteBySig(proposalId, support[i], vs[i], rs[i], ss[i]);
        }
    }

    function buyFromNftMarketplace(NftMarketplace marketplace, address nftContract, uint nftId, uint maxPrice) external {
        if (!executing) revert MustBeCalledByCollector();

        uint price = marketplace.getPrice(nftContract, nftId);
        if (maxPrice <= price) revert PriceTooHigh(price, maxPrice);

        marketplace.buy{ value: price }(nftContract, nftId);
    }

    function hashProposal(
        address[] memory targets,
        uint[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public pure virtual returns (uint256) {
        return uint256(keccak256(abi.encode(targets, values, calldatas, descriptionHash)));
    }
}
