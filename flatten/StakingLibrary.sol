// Dependency file: contracts/interfaces/IChainConfig.sol

// SPDX-License-Identifier: GPL-3.0-only
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

// Root file: contracts/StakingLibrary.sol

pragma solidity ^0.8.0;

// import "contracts/interfaces/IChainConfig.sol";

library StakingLibrary {

    uint256 public constant BALANCE_COMPACT_PRECISION = 1e10;

    enum ValidatorStatus {
        NotFound,
        Active,
        Pending,
        Jail
    }

    struct ValidatorSnapshot {
        uint96 totalRewards;
        uint112 totalDelegated;
        uint32 slashesCount;
        uint16 commissionRate;
    }

    struct Validator {
        address validatorAddress;
        address ownerAddress;
        ValidatorStatus status;
        uint64 changedAt;
        uint64 jailedBefore;
        uint64 claimedAt;
    }

    struct DelegationOpDelegate {
        uint112 amount;
        uint64 epoch;
    }

    struct DelegationOpUndelegate {
        uint112 amount;
        uint64 epoch;
    }

    struct ValidatorDelegation {
        DelegationOpDelegate[] delegateQueue;
        uint64 delegateGap;
        DelegationOpUndelegate[] undelegateQueue;
        uint64 undelegateGap;
    }

    event ValidatorDeposited(address indexed validator, uint256 amount, uint64 epoch);

    event VatTransferred(address indexed validator, uint256 amount);
    event WhtTransferred(address indexed validator, uint256 amount);

    event JdnRewardTransferred(address indexed validator, address receiver, uint256 amount);
    event ValidatorRewardTransferred(address indexed validator, address receiver, uint256 amount);    

    function _currentEpoch(
        IChainConfig _chainConfigContract
    ) internal view returns (uint64) {
        return uint64(block.number / _chainConfigContract.getEpochBlockInterval() + 0);
    }

    function touchValidatorSnapshot(
        mapping(address => mapping(uint64 => StakingLibrary.ValidatorSnapshot)) storage _validatorSnapshots,
        StakingLibrary.Validator memory validator, uint64 epoch
    ) public returns (StakingLibrary.ValidatorSnapshot storage) {
        StakingLibrary.ValidatorSnapshot storage snapshot = _validatorSnapshots[validator.validatorAddress][epoch];
        // if snapshot is already initialized then just return it
        if (snapshot.totalDelegated > 0) {
            return snapshot;
        }
        // find previous snapshot to copy parameters from it
        StakingLibrary.ValidatorSnapshot memory lastModifiedSnapshot = _validatorSnapshots[validator.validatorAddress][validator.changedAt];
        // last modified snapshot might store zero value, for first delegation it might happen and its not critical
        snapshot.totalDelegated = lastModifiedSnapshot.totalDelegated;
        snapshot.commissionRate = lastModifiedSnapshot.commissionRate;
        // we must save last affected epoch for this validator to be able to restore total delegated
        // amount in the future (check condition upper)
        if (epoch > validator.changedAt) {
            validator.changedAt = epoch;
        }
        return snapshot;
    }

        function depositFee(
            mapping(address => mapping(uint64 => StakingLibrary.ValidatorSnapshot)) storage _validatorSnapshots,
            mapping(address => StakingLibrary.Validator) storage _validatorsMap,
            IChainConfig _chainConfigContract,
            address validatorAddress
        ) public {
        require(msg.value > 0, "Staking: deposit is zero");
        // make sure validator is active
        StakingLibrary.Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.status != StakingLibrary.ValidatorStatus.NotFound, "Staking: validator not found");
        uint64 epoch = _currentEpoch(_chainConfigContract);

        // split deposit amount
        (uint256 jdnAmount, uint256 validatorAmount, uint256 stakersAmount) = _getSplitAmounts(_chainConfigContract, msg.value);

        IChainConfig.TaxPercent memory taxPercent = _chainConfigContract.getTaxPercent();
        uint256 jdnReward = _computeTax(_chainConfigContract, validatorAddress, jdnAmount, taxPercent.vat, taxPercent.whtCompany);
        uint256 validatorReward = _computeTax(_chainConfigContract, validatorAddress, validatorAmount, taxPercent.vat, taxPercent.whtCompany);
        uint256 stakersReward = _computeTax(_chainConfigContract, validatorAddress, stakersAmount, taxPercent.vat, taxPercent.whtIndividual);

        _transferNative(_chainConfigContract.getJdnWalletAddress(), jdnReward);        
        _transferNative(validatorAddress, validatorReward);

        // increase total pending rewards for validator for current epoch
        StakingLibrary.ValidatorSnapshot storage currentSnapshot = touchValidatorSnapshot(_validatorSnapshots, validator, epoch);
        currentSnapshot.totalRewards += uint96(stakersReward);

        emit ValidatorDeposited(validatorAddress, msg.value, epoch);
        emit JdnRewardTransferred(validatorAddress, _chainConfigContract.getJdnWalletAddress(), jdnReward);
        emit ValidatorRewardTransferred(validatorAddress, validatorAddress, validatorReward);
    }

    function _getSplitAmounts(
        IChainConfig _chainConfigContract,
        uint256 amount
    ) internal view returns (uint256 JDNAmount, uint256 validatorAmount, uint256 stakersAmount) {
        IChainConfig.SplitPercent memory splitPercent = _chainConfigContract.getSplitPercent();
        JDNAmount = (splitPercent.jdn * amount) / (_chainConfigContract.getPercentPrecision() * 100);
        validatorAmount = (splitPercent.validator * amount) / (_chainConfigContract.getPercentPrecision() * 100);
        stakersAmount = (splitPercent.stakers * amount) / (_chainConfigContract.getPercentPrecision() * 100);
    }

    function _computeTax(
        IChainConfig _chainConfigContract,
        address validatorAddress, uint256 amount, uint32 vatPercent, uint32 whtPercent
    ) internal returns (uint256 leftAmount) {
        uint256 vatAmount = (vatPercent * amount) / (_chainConfigContract.getPercentPrecision() * 100);
        uint256 beforeVatAmount = amount - vatAmount;
        uint256 whtAmount = (whtPercent * beforeVatAmount) / (_chainConfigContract.getPercentPrecision() * 100);
        leftAmount = amount - vatAmount - whtAmount;

        _transferNative(_chainConfigContract.getVatWalletAddress(), vatAmount);
        _transferNative(_chainConfigContract.getWhtWalletAddress(), whtAmount);

        emit VatTransferred(validatorAddress, vatAmount);
        emit WhtTransferred(validatorAddress, whtAmount);
    }

    function _transferNative(address receiver, uint256 amount) internal {
        (bool sent, ) = payable(receiver).call{value: amount}("");
        require(sent, "fail to send native");
    }

    function calcDelegatorRewardsAndPendingUndelegates(
        IChainConfig _chainConfigContract,
        mapping(address => mapping(address => StakingLibrary.ValidatorDelegation)) storage _validatorDelegations,
        mapping(address => mapping(uint64 => StakingLibrary.ValidatorSnapshot)) storage _validatorSnapshots,
        address validator, 
        address delegator, 
        uint64 beforeEpoch, 
        bool withUndelegate
    ) public view returns (uint256) {
        StakingLibrary.ValidatorDelegation memory delegation = _validatorDelegations[validator][delegator];
        uint256 availableFunds = 0;
        // process delegate queue to calculate staking rewards
        while (delegation.delegateGap < delegation.delegateQueue.length) {
            StakingLibrary.DelegationOpDelegate memory delegateOp = delegation.delegateQueue[delegation.delegateGap];
            if (delegateOp.epoch >= beforeEpoch) {
                break;
            }
            uint256 voteChangedAtEpoch = 0;
            if (delegation.delegateGap < delegation.delegateQueue.length - 1) {
                voteChangedAtEpoch = delegation.delegateQueue[delegation.delegateGap + 1].epoch;
            }
            for (; delegateOp.epoch < beforeEpoch && (voteChangedAtEpoch == 0 || delegateOp.epoch < voteChangedAtEpoch); delegateOp.epoch++) {
                StakingLibrary.ValidatorSnapshot memory validatorSnapshot = _validatorSnapshots[validator][delegateOp.epoch];
                if (validatorSnapshot.totalDelegated == 0) {
                    continue;
                }
                (uint256 delegatorFee, /*uint256 ownerFee*/, /*uint256 systemFee*/) = calcValidatorSnapshotEpochPayout(_chainConfigContract, validatorSnapshot);
                availableFunds += delegatorFee * delegateOp.amount / validatorSnapshot.totalDelegated;
            }
            ++delegation.delegateGap;
        }
        // process all items from undelegate queue
        while (withUndelegate && delegation.undelegateGap < delegation.undelegateQueue.length) {
            StakingLibrary.DelegationOpUndelegate memory undelegateOp = delegation.undelegateQueue[delegation.undelegateGap];
            if (undelegateOp.epoch > beforeEpoch) {
                break;
            }
            availableFunds += uint256(undelegateOp.amount) * BALANCE_COMPACT_PRECISION;
            ++delegation.undelegateGap;
        }
        // return available for claim funds
        return availableFunds;
    }

    function calcValidatorSnapshotEpochPayout(
        IChainConfig _chainConfigContract,
        StakingLibrary.ValidatorSnapshot memory validatorSnapshot
    ) public view returns (uint256 delegatorFee, uint256 ownerFee, uint256 systemFee) {
        // detect validator slashing to transfer all rewards to treasury
        if (validatorSnapshot.slashesCount >= _chainConfigContract.getMisdemeanorThreshold()) {
            return (delegatorFee = 0, ownerFee = 0, systemFee = validatorSnapshot.totalRewards);
        } else if (validatorSnapshot.totalDelegated == 0) {
            return (delegatorFee = 0, ownerFee = validatorSnapshot.totalRewards, systemFee = 0);
        }
        // ownerFee_(18+4-4=18) = totalRewards_18 * commissionRate_4 / 1e4
        ownerFee = uint256(validatorSnapshot.totalRewards) * validatorSnapshot.commissionRate / 1e4;
        // delegatorRewards = totalRewards - ownerFee
        delegatorFee = validatorSnapshot.totalRewards - ownerFee;
        // default system fee is zero for epoch
        systemFee = 0;
    }
}