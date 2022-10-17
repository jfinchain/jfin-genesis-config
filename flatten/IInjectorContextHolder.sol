// Dependency file: contracts/interfaces/ISlashingIndicator.sol

// SPDX-License-Identifier: GPL-3.0-only
// pragma solidity ^0.8.0;

interface ISlashingIndicator {

    function slash(address validator) external;
}

// Dependency file: contracts/interfaces/ISystemReward.sol

// pragma solidity ^0.8.0;

interface ISystemReward {

    function updateDistributionShare(address[] calldata accounts, uint16[] calldata shares) external;

    function getSystemFee() external view returns (uint256);

    function claimSystemFee() external;
}

// Dependency file: contracts/interfaces/IGovernance.sol

// pragma solidity ^0.8.0;

interface IGovernance {

    function getVotingSupply() external view returns (uint256);

    function getVotingPower(address validator) external view returns (uint256);
}


// Dependency file: contracts/interfaces/IValidatorSet.sol

// pragma solidity ^0.8.0;

interface IValidatorSet {

    function getValidators() external view returns (address[] memory);

    function deposit(address validator) external payable;
}

// Dependency file: contracts/interfaces/IStaking.sol

// pragma solidity ^0.8.0;

// import "contracts/interfaces/IValidatorSet.sol";

interface IStaking is IValidatorSet {

    function currentEpoch() external view returns (uint64);

    function nextEpoch() external view returns (uint64);

    function isValidatorActive(address validator) external view returns (bool);

    function isValidator(address validator) external view returns (bool);

    function getValidatorStatus(address validator) external view returns (
        address ownerAddress,
        uint8 status,
        uint256 totalDelegated,
        uint32 slashesCount,
        uint64 changedAt,
        uint64 jailedBefore,
        uint64 claimedAt,
        uint16 commissionRate,
        uint96 totalRewards
    );

    function getValidatorStatusAtEpoch(address validator, uint64 epoch) external view returns (
        address ownerAddress,
        uint8 status,
        uint256 totalDelegated,
        uint32 slashesCount,
        uint64 changedAt,
        uint64 jailedBefore,
        uint64 claimedAt,
        uint16 commissionRate,
        uint96 totalRewards
    );

    function getValidatorByOwner(address owner) external view returns (address);

    function addValidator(address validator) external;

    function removeValidator(address validator) external;

    function activateValidator(address validator) external;

    function disableValidator(address validator) external;

    function releaseValidatorFromJail(address validator) external;

    function getValidatorDelegation(address validator, address delegator) external view returns (
        uint256 delegatedAmount,
        uint64 atEpoch
    );

    function delegate(address validator) payable external;

    function undelegate(address validator, uint256 amount) external;

    function getValidatorFee(address validator) external view returns (uint256);

    function getPendingValidatorFee(address validator) external view returns (uint256);

    function claimValidatorFee(address validator) external;

    function getDelegatorFee(address validator, address delegator) external view returns (uint256);

    function getPendingDelegatorFee(address validator, address delegator) external view returns (uint256);

    function claimDelegatorFee(address validator) external;

    function calcAvailableForRedelegateAmount(address validator, address delegator) external view returns (uint256 amountToStake, uint256 rewardsDust);

    function claimPendingUndelegates(address validator) external;

    function redelegateDelegatorFee(address validator) external;

    function slash(address validator) external;
}

// Dependency file: contracts/interfaces/IDeployerProxy.sol

// pragma solidity ^0.8.0;

interface IDeployerProxy {

    function registerDeployedContract(address account, address impl) external;

    function checkContractActive(address impl) external;

    function isDeployer(address account) external view returns (bool);

    function getContractState(address contractAddress) external view returns (uint8 state, address impl, address deployer);

    function isBanned(address account) external view returns (bool);

    function addDeployer(address account) external;

    function banDeployer(address account) external;

    function unbanDeployer(address account) external;

    function removeDeployer(address account) external;

    function disableContract(address contractAddress) external;

    function enableContract(address contractAddress) external;
}

// Dependency file: contracts/interfaces/IStakingPool.sol

// pragma solidity ^0.8.0;

interface IStakingPool {

    function getStakedAmount(address validator, address staker) external view returns (uint256);

    function stake(address validator) external payable;

    function unstake(address validator, uint256 amount) external;

    function claimableRewards(address validator, address staker) external view returns (uint256);

    function claim(address validator) external;
}

// Dependency file: contracts/interfaces/IChainConfig.sol

// pragma solidity ^0.8.0;

interface IChainConfig {
    
    struct SplitPercent {
        uint32 jdn;
        uint32 validator;
        uint32 stakers;
    }

    struct TaxPercent {
        uint32 vat;
        uint32 whtCompany;
        uint32 whtIndividual;
    }

    function getActiveValidatorsLength() external view returns (uint32);

    function setActiveValidatorsLength(uint32 newValue) external;

    function getEpochBlockInterval() external view returns (uint32);

    function setEpochBlockInterval(uint32 newValue) external;

    function getMisdemeanorThreshold() external view returns (uint32);

    function setMisdemeanorThreshold(uint32 newValue) external;

    function getFelonyThreshold() external view returns (uint32);

    function setFelonyThreshold(uint32 newValue) external;

    function getValidatorJailEpochLength() external view returns (uint32);

    function setValidatorJailEpochLength(uint32 newValue) external;

    function getUndelegatePeriod() external view returns (uint32);

    function setUndelegatePeriod(uint32 newValue) external;

    function getMinValidatorStakeAmount() external view returns (uint256);

    function setMinValidatorStakeAmount(uint256 newValue) external;

    function getMinStakingAmount() external view returns (uint256);

    function setMinStakingAmount(uint256 newValue) external;
    
    function getMinTotalDelegatedAmount() external view returns (uint256);

    function setMinTotalDelegatedAmount(uint256 newValue) external;

    function getJdnWalletAddress() external view returns (address);

    function setJdnWalletAddress(address newValue) external;

    function getVatWalletAddress() external view returns (address);

    function setVatWalletAddress(address newValue) external;

    function getWhtWalletAddress() external view returns (address);

    function setWhtWalletAddress(address newValue) external;

    function getSplitPercent() external view returns (SplitPercent memory);

    function setSplitPercent(SplitPercent memory newValue) external;

    function getTaxPercent() external view returns (TaxPercent memory);
    
    function setTaxPercent(TaxPercent memory newValue) external;

    function getPercentPrecision() external view returns (uint32);
}

// Root file: contracts/interfaces/IInjectorContextHolder.sol

pragma solidity ^0.8.0;

// import "contracts/interfaces/ISlashingIndicator.sol";
// import "contracts/interfaces/ISystemReward.sol";
// import "contracts/interfaces/IGovernance.sol";
// import "contracts/interfaces/IStaking.sol";
// import "contracts/interfaces/IDeployerProxy.sol";
// import "contracts/interfaces/IStakingPool.sol";
// import "contracts/interfaces/IChainConfig.sol";

interface IInjectorContextHolder {

    function useDelayedInitializer(bytes memory delayedInitializer) external;

    function init() external;

    function isInitialized() external view returns (bool);
}