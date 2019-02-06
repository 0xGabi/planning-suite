pragma solidity ^0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/os/contracts/lib/math/SafeMath.sol";

/*******************************************************************************
    Copyright 2018, That Planning Suite

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*******************************************************************************/
/*******************************************************************************
* @title Projects Contract
* @author Kevin Siegler
* @dev This contract defines a registry for Github issues in addition to
* applying bounties in bulk and accepting fulfillment via this contract
*******************************************************************************/
interface Bounties {
    function issueBounty(
        address _issuer,
        uint _deadline,
        string _data,
        uint256 _fulfillmentAmount,
        address _arbiter,
        bool _paysTokens,
        address _tokenContract
    ) external returns (uint);  

    function activateBounty(
        uint _bountyId, 
        uint _value
    ) external payable;

    function acceptFulfillment(
        uint _bountyId, 
        uint _fulfillmentId
    ) external;
}


contract Projects is AragonApp {
    using SafeMath for uint256;
    Bounties bounties;

////////////////
// Constructor
////////////////

    function initialize(address _bountiesAddr)//, Vault _vault
    external onlyInit // solium-disable-line visibility-first
    {
        //vault = _vault.ethConnectorBase();
        bounties = Bounties(_bountiesAddr); // Standard Bounties instance

        _changeBountySettings(
            "100\tBeginner\t300\tIntermediate\t500\tAdvanced",
            3000, // baseRate
            336, // bountyDeadline
            "FTL", // bountyCurrency
            0x0000000000000000000000000000000000000000, // bountyAllocator
            0x0000000000000000000000000000000000000000 //bountyArbiter
        );

        initialized();
    }

    struct BountySettings {
        string expLevels;
        uint256 baseRate;
        uint256 bountyDeadline;
        string bountyCurrency;
        address bountyAllocator;
        address bountyArbiter;
    }

    BountySettings settings;

    struct GithubRepo {
        bytes20 owner; // repo owner's id on github
        mapping(uint256 => GithubIssue) issues;
        uint index;
    }

    struct GithubIssue {
        bytes32 repo;  // This is the internal repo identifier
        uint256 number; // May be redundant tracking this
        bool hasBounty;
        uint256 bountySize;
        uint256 priority;
        address bountyWallet; // Not sure if we'll have a way to "retrieve" this value from status open bounties
        uint standardBountyId;
    }

    // The entries in the repos registry.
    mapping(bytes32 => GithubRepo) private repos;

    // Gives us a repos array so we can actually iterate
    bytes32[] private repoIndex;

    // Fired when a repository is added to the registry.
    event RepoAdded(bytes32 indexed repoId, bytes20 owner, uint index);
    // Fired when a repository is removed from the registry.
    event RepoRemoved(bytes32 indexed repoId, uint index);
    // Fired when a repo is updated in the registry
    event RepoUpdated(bytes32 indexed repoId, bytes20 newOwner, uint newIndex);
    // Fired when a bounty is added to a repo
    event BountyAdded(bytes20 owner, bytes32 repoId, uint256 issueNumber, uint256 bountySize);
    // Fired when an issue is curated
    event IssueCurated(bytes32 repoId);
    // Fired when fulfillment is accepted
    event FulfillmentAccepted(bytes32 repoId, uint256 issueNumber, uint fulfillmentId);
    // Fired when settings are changed
    event BountySettingsChanged();

    bytes32 public constant ADD_BOUNTY_ROLE =  keccak256("ADD_BOUNTY_ROLE");
    bytes32 public constant ADD_REPO_ROLE = keccak256("ADD_REPO_ROLE");
    bytes32 public constant CHANGE_SETTINGS_ROLE =  keccak256("CHANGE_SETTINGS_ROLE");
    bytes32 public constant CURATE_ISSUES_ROLE = keccak256("CURATE_ISSUES_ROLE");
    bytes32 public constant REMOVE_REPO_ROLE =  keccak256("REMOVE_REPO_ROLE");

    function curateIssues(
        address[] /*unused_Addresses*/, 
        uint256[] issuePriorities,
        uint256[] issueDescriptionIndices, 
        string /* unused_issueDescriptions*/,
        uint256[] issueRepos,
        uint256[] issueNumbers,
        uint256 /* unused_curationId */
    ) external isInitialized auth(CURATE_ISSUES_ROLE)
    {
        bytes32 repoId;
        //require(issuePriorities.length == unusedAddresses.length, "length mismatch: issuePriorites and unusedAddresses");
        require(issuePriorities.length == issueDescriptionIndices.length, "length mismatch: issuePriorites and issueDescriptionIdx");
        require(issueRepos.length == issueDescriptionIndices.length, "length mismatch: issueRepos and issueDescriptionIdx");
        require(issueRepos.length == issueNumbers.length, "length mismatch: issueRepos and issueNumbers");

        for (uint256 i = 0; i < issuePriorities.length; i++) {
            repoId = bytes32(issueRepos[i]);
            require(issuePriorities[i] != 999, "issue already curated");
            repos[repoId].issues[uint256(issueNumbers[i])].priority = issuePriorities[i];
            emit IssueCurated(repoId);
        }
    }
    
///////////////////////
// Set state functions
///////////////////////

    function changeBountySettings(
        string expLevels,
        uint256 baseRate,
        uint256 bountyDeadline,
        string bountyCurrency,
        address bountyAllocator,
        address bountyArbiter
    ) external auth(CHANGE_SETTINGS_ROLE)
    {
        _changeBountySettings(expLevels, baseRate, bountyDeadline, bountyCurrency, bountyAllocator, bountyArbiter);
    }

///////////////////////
// View state functions
///////////////////////

    /**
     * @notice Get issue data from the registry.
     * @param _repoId The id of the Github repo in the projects registry
     */
    function getIssue(bytes32 _repoId, uint256 _issueNumber) external view
    returns(bool hasBounty, uint standardBountyId)
    {
        GithubIssue storage issue = repos[_repoId].issues[_issueNumber];
        hasBounty = issue.hasBounty;
        standardBountyId = issue.standardBountyId;
    }

    /**
     * @notice Get registry size.
     */
    function getReposCount() external view returns (uint count) {
        return repoIndex.length;
    }

    /**
     * @notice Get an entry from the registry.
     * @param _repoId The id of the Github repo in the projects registry
     * @return owner repo's owner address
     * @return index the Github repo registry index
     */
    function getRepo(bytes32 _repoId) external view returns (bytes20 owner, uint index) {
        require(isRepoAdded(_repoId), "REPO_NOT_ADDED");
        return(repos[_repoId].owner, repos[_repoId].index);
    }

    /**
     * @notice Get general settings.
     * @return BountySettings
     */

    function getSettings() external view returns (
        string expLevels,
        uint256 baseRate,
        uint256 bountyDeadline,
        string bountyCurrency,
        address bountyAllocator,
        address bountyArbiter
    )
    {
        return (
            settings.expLevels,
            settings.baseRate,
            settings.bountyDeadline,
            settings.bountyCurrency,
            settings.bountyAllocator,
            settings.bountyArbiter
        );
    }

///////////////////////
// Repository functions
///////////////////////
    /**
     * @notice Add selected repository to Managed Projects 
     * @param _owner Github id of the entity that owns the repo to add
     * @param _repoId Github id of the repo to add
     * @return index for the added repo at the registry
     */
    function addRepo(
        bytes32 _repoId,
        bytes20 _owner
    ) external auth(ADD_REPO_ROLE) returns (uint index)
    {
        require(!isRepoAdded(_repoId), "REPO_ALREADY_ADDED");
        repos[_repoId].owner = _owner;
        repos[_repoId].index = repoIndex.push(_repoId) - 1;
        emit RepoAdded(_repoId, _owner, repos[_repoId].index);
        return repoIndex.length - 1;
    }

    /**
     * @notice Remove an entry from the projects registry.
     * @param _repoId The id of the Github repo in the projects registry
     */
    function removeRepo(
        bytes32 _repoId
    ) external auth(REMOVE_REPO_ROLE) returns(bool success)
    {
        require(isRepoAdded(_repoId), "REPO_NOT_ADDED");
        uint rowToDelete = repos[_repoId].index;
        bytes32 repoToMove = repoIndex[repoIndex.length - 1];
        repoIndex[rowToDelete] = repoToMove;
        repos[repoToMove].index = rowToDelete;
        repoIndex.length--;
        emit RepoRemoved(_repoId, rowToDelete);
        emit RepoUpdated(repoToMove, repos[repoToMove].owner, rowToDelete);
        return true;
    }

///////////////////
// Bounty functions
///////////////////

    /**
     * @notice accept a given fulfillment
     * @param _repoId The id of the Github repo in the projects registry
     * @param _issueNumber the index of the bounty
     * @param _bountyFulfillmentId the index of the fulfillment being accepted
     */
    function acceptFulfillment(
        bytes32 _repoId,
        uint256 _issueNumber,
        uint _bountyFulfillmentId
    ) external auth(ADD_BOUNTY_ROLE)
    {
        GithubIssue storage issue = repos[_repoId].issues[_issueNumber];
        bounties.acceptFulfillment(issue.standardBountyId, _bountyFulfillmentId);
        emit FulfillmentAccepted(_repoId, _issueNumber, _bountyFulfillmentId);
    }

    /**
     * @notice add bulk bounties
     * @param _repoId The id of the Github repo in the projects registry
     * @param _issueNumbers an array of bounty indexes
     * @param _bountySizes an array of bounty sizes
     * @param _deadlines an array of bounty deadlines
     * @param _tokenBounties an array of token bounties
     * @param _tokenContracts an array of token contracts
     * @param _ipfsAddresses a string of ipfs addresses
     */
    function addBounties(
        bytes32 _repoId,
        uint256[] _issueNumbers,
        uint256[] _bountySizes,
        uint256[] _deadlines,
        bool[] _tokenBounties,
        address[] _tokenContracts,
        string _ipfsAddresses
    ) public payable auth(ADD_BOUNTY_ROLE)
    {
        // ensure the transvalue passed equals transaction value
        checkTransValueEqualsMessageValue(msg.value, _bountySizes,_tokenBounties);
        
        string memory ipfsHash;
        uint standardBountyId;
        // submit the bounty to the StandardBounties contract
        for (uint i = 0; i < _bountySizes.length; i++) {
            ipfsHash = substring(_ipfsAddresses, i.mul(46), i.add(1).mul(46));
            standardBountyId = bounties.issueBounty(
                this,                           //    address _issuer
                _deadlines[i],                  //    uint256 _deadlines
                ipfsHash,                       //    parse input to get ipfs hash
                _bountySizes[i],                //    uint256 _fulfillmentAmount
                address(0),                     //    address _arbiter
                _tokenBounties[i],              //    bool _paysTokens
                address(_tokenContracts[i])     //    address _tokenContract
            );
            // Activate the bounty so it can be fulfilled
            bounties.activateBounty.value(_bountySizes[i])(standardBountyId, _bountySizes[i]);

            //Add bounty to local registry
            _addBounty(
                _repoId,
                _issueNumbers[i],
                standardBountyId,
                _bountySizes[i]
            );
        }
    }

///////////////////////
// Public utility functions
///////////////////////

    /**
     * @notice Checks if a repo exists in the registry
     * @param _repoId the github repo id to check
     * @return _repoId Id for newly added repo
     */
    function isRepoAdded(bytes32 _repoId) public view returns(bool isAdded) {
        if (repoIndex.length == 0)
            return false;
        return (repoIndex[repos[_repoId].index] == _repoId);
    }

///////////////////////
// Internal functions
///////////////////////

    function _changeBountySettings(
        string expLevels,
        uint256 baseRate,
        uint256 bountyDeadline,
        string bountyCurrency,
        address bountyAllocator,
        address bountyArbiter
    ) internal
    {
        settings.expLevels = expLevels;
        settings.baseRate = baseRate;
        settings.bountyDeadline = bountyDeadline;
        settings.bountyCurrency = bountyCurrency;
        settings.bountyAllocator = bountyAllocator;
        settings.bountyArbiter = bountyArbiter;

        emit BountySettingsChanged();
    }

    function _addBounty(
        bytes32 _repoId,
        uint256 _issueNumber,
        uint _standardBountyId,
        uint256 _bountySize
    ) internal
    {
        repos[_repoId].issues[_issueNumber] = GithubIssue(
            _repoId,
            _issueNumber,
            true,
            _bountySize,
            999,
            address(0),
            _standardBountyId
        );
        emit BountyAdded(
            repos[_repoId].owner,
            _repoId,
            _issueNumber,
            _bountySize
        );
    }

    function checkTransValueEqualsMessageValue(
        uint256 _msgValue,
        uint256[] _bountySizes,
        bool[] _tokenBounties
    ) internal pure
    {
        uint256 transValueTotal = 0;
        for (uint i = 0; i < _bountySizes.length; i++) {
            if (!(_tokenBounties[i])) {
                transValueTotal = transValueTotal.add(_bountySizes[i]);
            }
        }
        require(_msgValue == transValueTotal, "ETH sent to cover bounties does not match bounty total");
    }

    function substring(
        string str,
        uint startIndex,
        uint endIndex
    ) internal pure returns (string)
    {
        // first char is at location 0
        //IPFS addresses span from 0 (startindex) to 46 (endIndex)
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex-startIndex);
        for (uint i = startIndex; i < endIndex; i++) {
            result[i-startIndex] = strBytes[i];
        }
        return string(result);
    }

}
