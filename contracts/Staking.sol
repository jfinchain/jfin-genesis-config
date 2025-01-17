// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./InjectorContextHolder.sol";
import "./StakingLibrary.sol";

contract Staking is InjectorContextHolder, IStaking {

    /**
     * This constant indicates precision of storing compact balances in the storage or floating point. Since default
     * balance precision is 256 bits it might gain some overhead on the storage because we don't need to store such huge
     * amount range. That is why we compact balances in uint112 values instead of uint256. By managing this value
     * you can set the precision of your balances, aka min and max possible staking amount. This value depends
     * mostly on your asset price in USD, for example ETH costs 4000$ then if we use 1 ether precision it takes 4000$
     * as min amount that might be problematic for users to do the stake. We can set 1 gwei precision and in this case
     * we increase min staking amount in 1e9 times, but also decreases max staking amount or total amount of staked assets.
     *
     * Here is an universal formula, if your asset is cheap in USD equivalent, like ~1$, then use 1 ether precision,
     * otherwise it might be better to use 1 gwei precision or any other amount that your want.
     *
     * Also be careful with setting `minValidatorStakeAmount` and `minStakingAmount`, because these values has
     * the same precision as specified here. It means that if you set precision 1 ether, then min staking amount of 10
     * tokens should have 10 raw value. For 1 gwei precision 10 tokens min amount should be stored as 10000000000.
     *
     * For the 112 bits we have ~32 decimals lg(2**112)=33.71 (lets round to 32 for simplicity). We split this amount
     * into integer (24) and for fractional (8) parts. It means that we can have only 8 decimals after zero.
     *
     * Based in current params we have next min/max values:
     * - min staking amount: 0.00000001 or 1e-8
     * - max staking amount: 1000000000000000000000000 or 1e+24
     *
     * WARNING: precision must be a 1eN format (A=1, N>0)
     */
    // uint256 internal constant BALANCE_COMPACT_PRECISION = 1e10; // move to StakinkgLibrary library
    /**
     * Here is min/max commission rates. Lets don't allow to set more than 30% of validator commission, because it's
     * too big commission for validator. Commission rate is a percents divided by 100 stored with 0 decimals as percents*100 (=pc/1e2*1e4)
     *
     * Here is some examples:
     * + 0.3% => 0.3*100=30
     * + 3% => 3*100=300
     * + 30% => 30*100=3000
     */
    uint16 internal constant COMMISSION_RATE_MIN_VALUE = 0; // 0%
    uint16 internal constant COMMISSION_RATE_MAX_VALUE = 3000; // 30%
    /**
     * This gas limit is used for internal transfers, BSC doesn't support berlin and it
     * might cause problems with smart contracts who used to stake transparent proxies or
     * beacon proxies that have a lot of expensive SLOAD instructions.
     */
    uint64 internal constant TRANSFER_GAS_LIMIT = 30_000;
    /**
     * Some items are stored in the queues and we must iterate though them to
     * execute one by one. Somtimes gas might not be enough for the tx execution.
     */
    uint32 internal constant CLAIM_BEFORE_GAS = 100_000;

    // validator events
    event ValidatorAdded(address indexed validator, address owner, uint8 status, uint16 commissionRate);
    event ValidatorModified(address indexed validator, address owner, uint8 status, uint16 commissionRate);
    event ValidatorRemoved(address indexed validator);
    event ValidatorOwnerClaimed(address indexed validator, uint256 amount, uint64 epoch);
    event ValidatorSlashed(address indexed validator, uint32 slashes, uint64 epoch);
    event ValidatorJailed(address indexed validator, uint64 epoch);
    event ValidatorDeposited(address indexed validator, uint256 amount, uint64 epoch);
    event ValidatorReleased(address indexed validator, uint64 epoch);

    // staker events
    event Delegated(address indexed validator, address indexed staker, uint256 amount, uint64 epoch);
    event Undelegated(address indexed validator, address indexed staker, uint256 amount, uint64 epoch);
    event Claimed(address indexed validator, address indexed staker, uint256 amount, uint64 epoch);
    event Redelegated(address indexed validator, address indexed staker, uint256 amount, uint256 dust, uint64 epoch);
    

    // mapping from validator address to validator
    mapping(address => StakingLibrary.Validator) internal _validatorsMap;
    // mapping from validator owner to validator address
    mapping(address => address) internal _validatorOwners;
    // list of all validators that are in validators mapping
    address[] internal _activeValidatorsList;
    // mapping with stakers to validators at epoch (validator -> delegator -> delegation)
    mapping(address => mapping(address => StakingLibrary.ValidatorDelegation)) internal _validatorDelegations;
    // mapping with validator snapshots per each epoch (validator -> epoch -> snapshot)
    mapping(address => mapping(uint64 => StakingLibrary.ValidatorSnapshot)) internal _validatorSnapshots;

    constructor(
        IStaking stakingContract,
        ISlashingIndicator slashingIndicatorContract,
        ISystemReward systemRewardContract,
        IStakingPool stakingPoolContract,
        IGovernance governanceContract,
        IChainConfig chainConfigContract,
        IRuntimeUpgrade runtimeUpgradeContract,
        IDeployerProxy deployerProxyContract
    ) InjectorContextHolder(
        stakingContract,
        slashingIndicatorContract,
        systemRewardContract,
        stakingPoolContract,
        governanceContract,
        chainConfigContract,
        runtimeUpgradeContract,
        deployerProxyContract
    ) {
    }

    function initialize(address[] calldata validators, address[] calldata owners, uint256[] calldata initialStakes, uint16 commissionRate) external initializer {
        require(validators.length == owners.length && validators.length == initialStakes.length);
        uint256 totalStakes = 0;
        for (uint256 i = 0; i < validators.length; i++) {            
            _addValidator(validators[i], owners[i], StakingLibrary.ValidatorStatus.Active, commissionRate, initialStakes[i], 0);
            totalStakes += initialStakes[i];
        }
        require(address(this).balance == totalStakes);
    }

    function getValidatorDelegation(address validatorAddress, address delegator) external view override returns (
        uint256 delegatedAmount,
        uint64 atEpoch
    ) {
        StakingLibrary.ValidatorDelegation memory delegation = _validatorDelegations[validatorAddress][delegator];
        if (delegation.delegateQueue.length == 0) {
            return (delegatedAmount = 0, atEpoch = 0);
        }
        StakingLibrary.DelegationOpDelegate memory snapshot = delegation.delegateQueue[delegation.delegateQueue.length - 1];
        return (delegatedAmount = uint256(snapshot.amount) * StakingLibrary.BALANCE_COMPACT_PRECISION, atEpoch = snapshot.epoch);
    }

    function getValidatorStatus(address validatorAddress) external view override returns (
        address ownerAddress,
        uint8 status,
        uint256 totalDelegated,
        uint32 slashesCount,
        uint64 changedAt,
        uint64 jailedBefore,
        uint64 claimedAt,
        uint16 commissionRate,
        uint96 totalRewards
    ) {
        StakingLibrary.Validator memory validator = _validatorsMap[validatorAddress];
        StakingLibrary.ValidatorSnapshot memory snapshot = _validatorSnapshots[validator.validatorAddress][validator.changedAt];
        return (
        ownerAddress = validator.ownerAddress,
        status = uint8(validator.status),
        totalDelegated = uint256(snapshot.totalDelegated) * StakingLibrary.BALANCE_COMPACT_PRECISION,
        slashesCount = snapshot.slashesCount,
        changedAt = validator.changedAt,
        jailedBefore = validator.jailedBefore,
        claimedAt = validator.claimedAt,
        commissionRate = snapshot.commissionRate,
        totalRewards = snapshot.totalRewards
        );
    }

    function getValidatorStatusAtEpoch(address validatorAddress, uint64 epoch) external view returns (
        address ownerAddress,
        uint8 status,
        uint256 totalDelegated,
        uint32 slashesCount,
        uint64 changedAt,
        uint64 jailedBefore,
        uint64 claimedAt,
        uint16 commissionRate,
        uint96 totalRewards
    ) {
        StakingLibrary.Validator memory validator = _validatorsMap[validatorAddress];
        StakingLibrary.ValidatorSnapshot memory snapshot = _touchValidatorSnapshotImmutable(validator, epoch);
        return (
        ownerAddress = validator.ownerAddress,
        status = uint8(validator.status),
        totalDelegated = uint256(snapshot.totalDelegated) * StakingLibrary.BALANCE_COMPACT_PRECISION,
        slashesCount = snapshot.slashesCount,
        changedAt = validator.changedAt,
        jailedBefore = validator.jailedBefore,
        claimedAt = validator.claimedAt,
        commissionRate = snapshot.commissionRate,
        totalRewards = snapshot.totalRewards
        );
    }

    function getValidatorByOwner(address owner) external view override returns (address) {
        return _validatorOwners[owner];
    }

    function releaseValidatorFromJail(address validatorAddress) external override {
        // make sure validator is in jail
        StakingLibrary.Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.status == StakingLibrary.ValidatorStatus.Jail, "bad status");
        
        // only validator owner
        require(msg.sender == validator.ownerAddress, "only owner");
        require(currentEpoch() >= validator.jailedBefore, "still in jail");
        // release validator from jail
        _releaseValidatorFromJail(validator);
    }

    function forceUnJailValidator(address validatorAddress) external onlyFromGovernance {
        // make sure validator is in jail
        StakingLibrary.Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.status == StakingLibrary.ValidatorStatus.Jail, "bad status");
        // release validator from jail
        _releaseValidatorFromJail(validator);
    }

    function _releaseValidatorFromJail(StakingLibrary.Validator memory validator) internal {
        address validatorAddress = validator.validatorAddress;
        // update validator status
        validator.status = StakingLibrary.ValidatorStatus.Active;
        validator.jailedBefore = 0;
        _validatorsMap[validatorAddress] = validator;
        _activeValidatorsList.push(validatorAddress);
        // emit event
        emit ValidatorReleased(validatorAddress, currentEpoch());
    }

    function delegate(address validatorAddress) payable external override {
        _delegateTo(msg.sender, validatorAddress, msg.value);
    }

    function undelegate(address validatorAddress, uint256 amount) external override {
        _undelegateFrom(msg.sender, validatorAddress, amount);
    }

    function currentEpoch() public view returns (uint64) {
        return uint64(block.number / _CHAIN_CONFIG_CONTRACT.getEpochBlockInterval());
    }

    function nextEpoch() public view returns (uint64) {
        return currentEpoch() + 1;
    }

    function _touchValidatorSnapshotImmutable(StakingLibrary.Validator memory validator, uint64 epoch) internal view returns (StakingLibrary.ValidatorSnapshot memory) {
        StakingLibrary.ValidatorSnapshot memory snapshot = _validatorSnapshots[validator.validatorAddress][epoch];
        // if snapshot is already initialized then just return it
        if (snapshot.totalDelegated > 0) {
            return snapshot;
        }
        // find previous snapshot to copy parameters from it
        StakingLibrary.ValidatorSnapshot memory lastModifiedSnapshot = _validatorSnapshots[validator.validatorAddress][validator.changedAt];
        // last modified snapshot might store zero value, for first delegation it might happen and its not critical
        snapshot.totalDelegated = lastModifiedSnapshot.totalDelegated;
        snapshot.commissionRate = lastModifiedSnapshot.commissionRate;
        // return existing or new snapshot
        return snapshot;
    }

    function _delegateTo(address fromDelegator, address toValidator, uint256 amount) internal {
        // check is minimum delegate amount
        require(amount >= _CHAIN_CONFIG_CONTRACT.getMinStakingAmount() && amount != 0, "too low");
        require(amount % StakingLibrary.BALANCE_COMPACT_PRECISION == 0, "no remainder");
        // make sure amount is greater than min staking amount
        // make sure validator exists at least
        StakingLibrary.Validator memory validator = _validatorsMap[toValidator];
        require(validator.status != StakingLibrary.ValidatorStatus.NotFound, "not found");
        uint64 atEpoch = nextEpoch();
        // Lets upgrade next snapshot parameters:
        // + find snapshot for the next epoch after current block
        // + increase total delegated amount in the next epoch for this validator
        // + re-save validator because last affected epoch might change
        StakingLibrary.ValidatorSnapshot storage validatorSnapshot = StakingLibrary.touchValidatorSnapshot(_validatorSnapshots, validator, atEpoch);
        validatorSnapshot.totalDelegated += uint112(amount / StakingLibrary.BALANCE_COMPACT_PRECISION);
        _validatorsMap[toValidator] = validator;

        if (validator.status == StakingLibrary.ValidatorStatus.Active && 
            validatorSnapshot.totalDelegated < _CHAIN_CONFIG_CONTRACT.getMinTotalDelegatedAmount()) {
            disableValidator(validator.validatorAddress);
        } else if (validator.status == StakingLibrary.ValidatorStatus.Pending && 
            validatorSnapshot.totalDelegated >= _CHAIN_CONFIG_CONTRACT.getMinTotalDelegatedAmount()) {
            activateValidator(validator.validatorAddress);
        }

        // if last pending delegate has the same next epoch then its safe to just increase total
        // staked amount because it can't affect current validator set, but otherwise we must create
        // new record in delegation queue with the last epoch (delegations are ordered by epoch)
        StakingLibrary.ValidatorDelegation storage delegation = _validatorDelegations[toValidator][fromDelegator];
        if (delegation.delegateQueue.length > 0) {
            StakingLibrary.DelegationOpDelegate storage recentDelegateOp = delegation.delegateQueue[delegation.delegateQueue.length - 1];
            // if we already have pending snapshot for the next epoch then just increase new amount,
            // otherwise create next pending snapshot. (tbh it can't be greater, but what we can do here instead?)
            if (recentDelegateOp.epoch >= atEpoch) {
                recentDelegateOp.amount += uint112(amount / StakingLibrary.BALANCE_COMPACT_PRECISION);
            } else {
                delegation.delegateQueue.push(StakingLibrary.DelegationOpDelegate({epoch : atEpoch, amount : recentDelegateOp.amount + uint112(amount / StakingLibrary.BALANCE_COMPACT_PRECISION)}));
            }
        } else {
            // there is no any delegations at al, lets create the first one
            delegation.delegateQueue.push(StakingLibrary.DelegationOpDelegate({epoch : atEpoch, amount : uint112(amount / StakingLibrary.BALANCE_COMPACT_PRECISION)}));
        }
        // emit event with the next epoch
        emit Delegated(toValidator, fromDelegator, amount, atEpoch);
    }

    function _undelegateFrom(address toDelegator, address fromValidator, uint256 amount) internal {
        // check minimum delegate amount
        require(amount >= _CHAIN_CONFIG_CONTRACT.getMinStakingAmount() && amount != 0, "too low");
        require(amount % StakingLibrary.BALANCE_COMPACT_PRECISION == 0, "no remainder");
        // make sure validator exists at least
        StakingLibrary.Validator memory validator = _validatorsMap[fromValidator];
        uint64 beforeEpoch = nextEpoch();
        // Lets upgrade next snapshot parameters:
        // + find snapshot for the next epoch after current block
        // + increase total delegated amount in the next epoch for this validator
        // + re-save validator because last affected epoch might change
        StakingLibrary.ValidatorSnapshot storage validatorSnapshot = StakingLibrary.touchValidatorSnapshot(_validatorSnapshots, validator, beforeEpoch);
        require(validatorSnapshot.totalDelegated >= uint112(amount / StakingLibrary.BALANCE_COMPACT_PRECISION), "insufficient balance");
        validatorSnapshot.totalDelegated -= uint112(amount / StakingLibrary.BALANCE_COMPACT_PRECISION);
        _validatorsMap[fromValidator] = validator;

        if (validator.status == StakingLibrary.ValidatorStatus.Active && 
            validatorSnapshot.totalDelegated < _CHAIN_CONFIG_CONTRACT.getMinTotalDelegatedAmount()) {
            disableValidator(validator.validatorAddress);
        } else if (validator.status == StakingLibrary.ValidatorStatus.Pending && 
            validatorSnapshot.totalDelegated >= _CHAIN_CONFIG_CONTRACT.getMinTotalDelegatedAmount()) {
            activateValidator(validator.validatorAddress);
        }

        // if last pending delegate has the same next epoch then its safe to just increase total
        // staked amount because it can't affect current validator set, but otherwise we must create
        // new record in delegation queue with the last epoch (delegations are ordered by epoch)
        StakingLibrary.ValidatorDelegation storage delegation = _validatorDelegations[fromValidator][toDelegator];
        require(delegation.delegateQueue.length > 0, "insufficient balance");
        StakingLibrary.DelegationOpDelegate storage recentDelegateOp = delegation.delegateQueue[delegation.delegateQueue.length - 1];
        require(recentDelegateOp.amount >= uint64(amount / StakingLibrary.BALANCE_COMPACT_PRECISION), "insufficient balance");
        uint112 nextDelegatedAmount = recentDelegateOp.amount - uint112(amount / StakingLibrary.BALANCE_COMPACT_PRECISION);
        if (recentDelegateOp.epoch >= beforeEpoch) {
            // decrease total delegated amount for the next epoch
            recentDelegateOp.amount = nextDelegatedAmount;
        } else {
            // there is no pending delegations, so lets create the new one with the new amount
            delegation.delegateQueue.push(StakingLibrary.DelegationOpDelegate({epoch : beforeEpoch, amount : nextDelegatedAmount}));
        }
        // create new undelegate queue operation with soft lock
        delegation.undelegateQueue.push(StakingLibrary.DelegationOpUndelegate({amount : uint112(amount / StakingLibrary.BALANCE_COMPACT_PRECISION), epoch : beforeEpoch + _CHAIN_CONFIG_CONTRACT.getUndelegatePeriod()}));
        // emit event with the next epoch number
        emit Undelegated(fromValidator, toDelegator, amount, beforeEpoch);
    }

    function _transferDelegatorRewards(address validator, address delegator, uint64 beforeEpochExclude, bool withRewards, bool withUndelegates) internal {
        StakingLibrary.ValidatorDelegation storage delegation = _validatorDelegations[validator][delegator];
        // claim rewards and undelegates
        uint256 availableFunds = 0;
        if (withRewards) {
            availableFunds += _processDelegateQueue(validator, delegation, beforeEpochExclude);
        }
        if (withUndelegates) {
            availableFunds += _processUndelegateQueue(delegation, beforeEpochExclude);
        }
        // for transfer claim mode just all rewards to the user
        _safeTransferWithGasLimit(payable(delegator), availableFunds);
        // emit event
        emit Claimed(validator, delegator, availableFunds, beforeEpochExclude);
    }

    function _redelegateDelegatorRewards(address validator, address delegator, uint64 beforeEpochExclude, bool withRewards, bool withUndelegates) internal {
        StakingLibrary.ValidatorDelegation storage delegation = _validatorDelegations[validator][delegator];
        // claim rewards and undelegates
        uint256 availableFunds = 0;
        if (withRewards) {
            availableFunds += _processDelegateQueue(validator, delegation, beforeEpochExclude);
        }
        if (withUndelegates) {
            availableFunds += _processUndelegateQueue(delegation, beforeEpochExclude);
        }
        (uint256 amountToStake, uint256 rewardsDust) = _calcAvailableForRedelegateAmount(availableFunds);
        // if we have something to re-stake then delegate it to the validator
        if (amountToStake > 0) {
            _delegateTo(delegator, validator, amountToStake);
        }
        // if we have dust from staking then send it to user (we can't keep them in the contract)
        if (rewardsDust > 0) {
            _safeTransferWithGasLimit(payable(delegator), rewardsDust);
        }
        // emit event
        emit Redelegated(validator, delegator, amountToStake, rewardsDust, beforeEpochExclude);
    }

    function _processDelegateQueue(address validator, StakingLibrary.ValidatorDelegation storage delegation, uint64 beforeEpochExclude) internal returns (uint256 availableFunds) {
        uint64 delegateGap = delegation.delegateGap;
        for (uint256 queueLength = delegation.delegateQueue.length; delegateGap < queueLength && gasleft() > CLAIM_BEFORE_GAS;) {
            StakingLibrary.DelegationOpDelegate memory delegateOp = delegation.delegateQueue[delegateGap];
            if (delegateOp.epoch >= beforeEpochExclude) {
                break;
            }
            uint256 voteChangedAtEpoch = 0;
            if (delegateGap < queueLength - 1) {
                voteChangedAtEpoch = delegation.delegateQueue[delegateGap + 1].epoch;
            }
            for (; delegateOp.epoch < beforeEpochExclude && (voteChangedAtEpoch == 0 || delegateOp.epoch < voteChangedAtEpoch) && gasleft() > CLAIM_BEFORE_GAS; delegateOp.epoch++) {
                StakingLibrary.ValidatorSnapshot memory validatorSnapshot = _validatorSnapshots[validator][delegateOp.epoch];
                if (validatorSnapshot.totalDelegated == 0) {
                    continue;
                }
                (uint256 delegatorFee, /*uint256 ownerFee*/, /*uint256 systemFee*/) = _calcValidatorSnapshotEpochPayout(validatorSnapshot);
                availableFunds += delegatorFee * delegateOp.amount / validatorSnapshot.totalDelegated;
            }
            // if we have reached end of the delegation list then lets stay on the last item, but with updated latest processed epoch
            if (delegateGap >= queueLength - 1) {
                delegation.delegateQueue[delegateGap] = delegateOp;
                break;
            }
            delete delegation.delegateQueue[delegateGap];
            ++delegateGap;
        }
        delegation.delegateGap = delegateGap;
        return availableFunds;
    }

    function _processUndelegateQueue(StakingLibrary.ValidatorDelegation storage delegation, uint64 beforeEpochExclude) internal returns (uint256 availableFunds) {
        uint64 undelegateGap = delegation.undelegateGap;
        for (uint256 queueLength = delegation.undelegateQueue.length; undelegateGap < queueLength  && gasleft() > CLAIM_BEFORE_GAS;) {
            StakingLibrary.DelegationOpUndelegate memory undelegateOp = delegation.undelegateQueue[undelegateGap];
            if (undelegateOp.epoch > beforeEpochExclude) {
                break;
            }
            availableFunds += uint256(undelegateOp.amount) * StakingLibrary.BALANCE_COMPACT_PRECISION;
            delete delegation.undelegateQueue[undelegateGap];
            ++undelegateGap;
        }
        delegation.undelegateGap = undelegateGap;
        return availableFunds;
    }

    function _calcDelegatorRewardsAndPendingUndelegates(address validator, address delegator, uint64 beforeEpoch, bool withUndelegate) internal view returns (uint256) {
        return StakingLibrary.calcDelegatorRewardsAndPendingUndelegates(
            _CHAIN_CONFIG_CONTRACT,
            _validatorDelegations,
            _validatorSnapshots,
            validator, delegator, beforeEpoch, withUndelegate);
    }

    function _claimValidatorOwnerRewards(StakingLibrary.Validator storage validator, uint64 beforeEpoch) internal {
        uint256 availableFunds = 0;
        uint256 systemFee = 0;
        uint64 claimAt = validator.claimedAt;
        for (; claimAt < beforeEpoch && gasleft() > CLAIM_BEFORE_GAS; claimAt++) {
            StakingLibrary.ValidatorSnapshot memory validatorSnapshot = _validatorSnapshots[validator.validatorAddress][claimAt];
            (/*uint256 delegatorFee*/, uint256 ownerFee, uint256 slashingFee) = _calcValidatorSnapshotEpochPayout(validatorSnapshot);
            availableFunds += ownerFee;
            systemFee += slashingFee;
        }
        validator.claimedAt = claimAt;
        _safeTransferWithGasLimit(payable(validator.ownerAddress), availableFunds);
        // if we have system fee then pay it to treasury account
        if (systemFee > 0) {
            _unsafeTransfer(payable(address(_SYSTEM_REWARD_CONTRACT)), systemFee);
        }
        emit ValidatorOwnerClaimed(validator.validatorAddress, availableFunds, beforeEpoch);
    }

    function _calcValidatorOwnerRewards(StakingLibrary.Validator memory validator, uint64 beforeEpoch) internal view returns (uint256) {
        uint256 availableFunds = 0;
        for (; validator.claimedAt < beforeEpoch; validator.claimedAt++) {
            StakingLibrary.ValidatorSnapshot memory validatorSnapshot = _validatorSnapshots[validator.validatorAddress][validator.claimedAt];
            (/*uint256 delegatorFee*/, uint256 ownerFee, /*uint256 systemFee*/) = _calcValidatorSnapshotEpochPayout(validatorSnapshot);
            availableFunds += ownerFee;
        }
        return availableFunds;
    }

    function _calcValidatorSnapshotEpochPayout(StakingLibrary.ValidatorSnapshot memory validatorSnapshot) internal view returns (uint256 delegatorFee, uint256 ownerFee, uint256 systemFee) {
        return StakingLibrary.calcValidatorSnapshotEpochPayout(_CHAIN_CONFIG_CONTRACT, validatorSnapshot);
    }

    function registerValidator(address validatorAddress, uint16 commissionRate) payable external override {
        uint256 initialStake = msg.value;
        // // initial stake amount should be greater than minimum validator staking amount
        require(initialStake >= _CHAIN_CONFIG_CONTRACT.getMinValidatorStakeAmount(), "too low");
        require(initialStake % StakingLibrary.BALANCE_COMPACT_PRECISION == 0, "no remainder");
        // add new validator as pending
        _addValidator(validatorAddress, msg.sender, StakingLibrary.ValidatorStatus.Pending, commissionRate, initialStake, nextEpoch());
    }

    function addValidator(address account) external onlyFromGovernance virtual override {
        _addValidator(account, account, StakingLibrary.ValidatorStatus.Active, 0, 0, nextEpoch());
    }

    function _addValidator(address validatorAddress, address validatorOwner, StakingLibrary.ValidatorStatus status, uint16 commissionRate, uint256 initialStake, uint64 sinceEpoch) internal {
        // validator commission rate
        require(commissionRate >= COMMISSION_RATE_MIN_VALUE && commissionRate <= COMMISSION_RATE_MAX_VALUE, "bad commission");
        // init validator default params
        StakingLibrary.Validator memory validator = _validatorsMap[validatorAddress];
        require(_validatorsMap[validatorAddress].status == StakingLibrary.ValidatorStatus.NotFound, "already exist");
        validator.validatorAddress = validatorAddress;
        validator.ownerAddress = validatorOwner;
        validator.status = status;
        validator.changedAt = sinceEpoch;
        _validatorsMap[validatorAddress] = validator;
        // save validator owner
        require(_validatorOwners[validatorOwner] == address(0x00), "owner in use");
        _validatorOwners[validatorOwner] = validatorAddress;
        // add new validator to array
        if (status == StakingLibrary.ValidatorStatus.Active) {
            _activeValidatorsList.push(validatorAddress);
        }
        // push initial validator snapshot at zero epoch with default params
        _validatorSnapshots[validatorAddress][sinceEpoch] = StakingLibrary.ValidatorSnapshot(0, uint112(initialStake / StakingLibrary.BALANCE_COMPACT_PRECISION), 0, commissionRate);
        // delegate initial stake to validator owner
        StakingLibrary.ValidatorDelegation storage delegation = _validatorDelegations[validatorAddress][validatorOwner];
        require(delegation.delegateQueue.length == 0);
        delegation.delegateQueue.push(StakingLibrary.DelegationOpDelegate(uint112(initialStake / StakingLibrary.BALANCE_COMPACT_PRECISION), sinceEpoch));
        emit Delegated(validatorAddress, validatorOwner, initialStake, sinceEpoch);
        // emit event
        emit ValidatorAdded(validatorAddress, validatorOwner, uint8(status), commissionRate);
    }

    function removeValidator(address account) external onlyFromGovernance virtual override {
        StakingLibrary.Validator memory validator = _validatorsMap[account];
        require(validator.status != StakingLibrary.ValidatorStatus.NotFound, "not found");
        // remove validator from active list if exists
        _removeValidatorFromActiveList(account);
        // remove from validators map
        delete _validatorOwners[validator.ownerAddress];
        delete _validatorsMap[account];
        // emit event about it
        emit ValidatorRemoved(account);
    }

    function _removeValidatorFromActiveList(address validatorAddress) internal {
        // find index of validator in validator set
        int256 indexOf = - 1;
        for (uint256 i = 0; i < _activeValidatorsList.length; i++) {
            if (_activeValidatorsList[i] != validatorAddress) continue;
            indexOf = int256(i);
            break;
        }
        // remove validator from array (since we remove only active it might not exist in the list)
        if (indexOf >= 0) {
            if (_activeValidatorsList.length > 1 && uint256(indexOf) != _activeValidatorsList.length - 1) {
                _activeValidatorsList[uint256(indexOf)] = _activeValidatorsList[_activeValidatorsList.length - 1];
            }
            _activeValidatorsList.pop();
        }
    }

    function activateValidator(address validatorAddress) public onlyFromGovernance virtual override {
        StakingLibrary.Validator memory validator = _validatorsMap[validatorAddress];
        require(_validatorsMap[validatorAddress].status == StakingLibrary.ValidatorStatus.Pending, "bad status");
        _activeValidatorsList.push(validatorAddress);
        validator.status = StakingLibrary.ValidatorStatus.Active;
        _validatorsMap[validatorAddress] = validator;
        StakingLibrary.ValidatorSnapshot storage snapshot = StakingLibrary.touchValidatorSnapshot(_validatorSnapshots, validator, nextEpoch());
        emit ValidatorModified(validatorAddress, validator.ownerAddress, uint8(validator.status), snapshot.commissionRate);
    }

    function disableValidator(address validatorAddress) public onlyFromGovernance virtual override {
        StakingLibrary.Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.status == StakingLibrary.ValidatorStatus.Active || validator.status == StakingLibrary.ValidatorStatus.Jail, "bad status");
        _removeValidatorFromActiveList(validatorAddress);
        validator.status = StakingLibrary.ValidatorStatus.Pending;
        _validatorsMap[validatorAddress] = validator;
        StakingLibrary.ValidatorSnapshot storage snapshot = StakingLibrary.touchValidatorSnapshot(_validatorSnapshots, validator, nextEpoch());
        emit ValidatorModified(validatorAddress, validator.ownerAddress, uint8(validator.status), snapshot.commissionRate);
    }

    function changeValidatorCommissionRate(address validatorAddress, uint16 commissionRate) external {
        require(commissionRate >= COMMISSION_RATE_MIN_VALUE && commissionRate <= COMMISSION_RATE_MAX_VALUE, "bad commission");
        StakingLibrary.Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.status != StakingLibrary.ValidatorStatus.NotFound, "not found");
        require(validator.ownerAddress == msg.sender, "only owner");
        StakingLibrary.ValidatorSnapshot storage snapshot = StakingLibrary.touchValidatorSnapshot(_validatorSnapshots, validator, nextEpoch());
        snapshot.commissionRate = commissionRate;
        _validatorsMap[validatorAddress] = validator;
        emit ValidatorModified(validator.validatorAddress, validator.ownerAddress, uint8(validator.status), commissionRate);
    }

    function changeValidatorOwner(address validatorAddress, address newOwner) external override {
        StakingLibrary.Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.ownerAddress == msg.sender, "only owner");
        require(_validatorOwners[newOwner] == address(0x00), "owner in use");
        delete _validatorOwners[validator.ownerAddress];
        validator.ownerAddress = newOwner;
        _validatorOwners[newOwner] = validatorAddress;
        _validatorsMap[validatorAddress] = validator;
        StakingLibrary.ValidatorSnapshot storage snapshot = StakingLibrary.touchValidatorSnapshot(_validatorSnapshots, validator, nextEpoch());
        emit ValidatorModified(validator.validatorAddress, validator.ownerAddress, uint8(validator.status), snapshot.commissionRate);
    }

    function isValidatorActive(address account) external override view returns (bool) {
        if (_validatorsMap[account].status != StakingLibrary.ValidatorStatus.Active) {
            return false;
        }
        address[] memory topValidators = getValidators();
        for (uint256 i = 0; i < topValidators.length; i++) {
            if (topValidators[i] == account) return true;
        }
        return false;
    }

    function isValidator(address account) external override view returns (bool) {
        return _validatorsMap[account].status != StakingLibrary.ValidatorStatus.NotFound;
    }

    function getValidators() public view override returns (address[] memory) {
        uint256 n = _activeValidatorsList.length;
        address[] memory orderedValidators = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            orderedValidators[i] = _activeValidatorsList[i];
        }
        // we need to select k top validators out of n
        uint256 k = _CHAIN_CONFIG_CONTRACT.getActiveValidatorsLength();
        if (k > n) {
            k = n;
        }
        for (uint256 i = 0; i < k; i++) {
            uint256 nextValidator = i;
            StakingLibrary.Validator memory currentMax = _validatorsMap[orderedValidators[nextValidator]];
            StakingLibrary.ValidatorSnapshot memory maxSnapshot = _validatorSnapshots[currentMax.validatorAddress][currentMax.changedAt];
            for (uint256 j = i + 1; j < n; j++) {
                StakingLibrary.Validator memory current = _validatorsMap[orderedValidators[j]];
                StakingLibrary.ValidatorSnapshot memory currentSnapshot = _validatorSnapshots[current.validatorAddress][current.changedAt];
                if (maxSnapshot.totalDelegated < currentSnapshot.totalDelegated) {
                    nextValidator = j;
                    currentMax = current;
                    maxSnapshot = currentSnapshot;
                }
            }
            address backup = orderedValidators[i];
            orderedValidators[i] = orderedValidators[nextValidator];
            orderedValidators[nextValidator] = backup;
        }
        // this is to cut array to first k elements without copying
        assembly {
            mstore(orderedValidators, k)
        }
        return orderedValidators;
    }

    function deposit(address validatorAddress) external payable onlyFromCoinbase virtual override {
        StakingLibrary.depositFee(_validatorSnapshots, _validatorsMap, _CHAIN_CONFIG_CONTRACT, validatorAddress);
    }

    function getValidatorFee(address validatorAddress) external override view returns (uint256) {
        // make sure validator exists at least
        StakingLibrary.Validator memory validator = _validatorsMap[validatorAddress];
        if (validator.status == StakingLibrary.ValidatorStatus.NotFound) {
            return 0;
        }
        // calc validator rewards
        return _calcValidatorOwnerRewards(validator, currentEpoch());
    }

    function getPendingValidatorFee(address validatorAddress) external override view returns (uint256) {
        // make sure validator exists at least
        StakingLibrary.Validator memory validator = _validatorsMap[validatorAddress];
        if (validator.status == StakingLibrary.ValidatorStatus.NotFound) {
            return 0;
        }
        // calc validator rewards
        return _calcValidatorOwnerRewards(validator, nextEpoch());
    }

    function claimValidatorFee(address validatorAddress) external override {
        // make sure validator exists at least
        StakingLibrary.Validator storage validator = _validatorsMap[validatorAddress];
        // only validator owner can claim deposit fee
        require(msg.sender == validator.ownerAddress, "only owner");
        // claim all validator fees
        _claimValidatorOwnerRewards(validator, currentEpoch());
    }

    function getDelegatorFee(address validatorAddress, address delegatorAddress) external override view returns (uint256) {
        return _calcDelegatorRewardsAndPendingUndelegates(validatorAddress, delegatorAddress, currentEpoch(), true);
    }

    function getPendingDelegatorFee(address validatorAddress, address delegatorAddress) external override view returns (uint256) {
        return _calcDelegatorRewardsAndPendingUndelegates(validatorAddress, delegatorAddress, nextEpoch(), true);
    }

    function claimDelegatorFee(address validatorAddress) external override {
        // claim all confirmed delegator fees including undelegates
        _transferDelegatorRewards(validatorAddress, msg.sender, currentEpoch(), true, true);
    }

    function claimPendingUndelegates(address validator) external override {
        // claim only pending undelegates
        _transferDelegatorRewards(validator, msg.sender, currentEpoch(), false, true);
    }

    function _calcAvailableForRedelegateAmount(uint256 claimableRewards) internal view returns (uint256 amountToStake, uint256 rewardsDust) {
        // for redelegate we must split amount into stake-able and dust
        amountToStake = (claimableRewards / StakingLibrary.BALANCE_COMPACT_PRECISION) * StakingLibrary.BALANCE_COMPACT_PRECISION;
        if (amountToStake < _CHAIN_CONFIG_CONTRACT.getMinStakingAmount()) {
            return (0, claimableRewards);
        }
        // if we have dust remaining after re-stake then send it to user (we can't keep it in the contract)
        return (amountToStake, claimableRewards - amountToStake);
    }

    function calcAvailableForRedelegateAmount(address validator, address delegator) external view override returns (uint256 amountToStake, uint256 rewardsDust) {
        uint256 claimableRewards = _calcDelegatorRewardsAndPendingUndelegates(validator, delegator, currentEpoch(), false);
        return _calcAvailableForRedelegateAmount(claimableRewards);
    }

    function redelegateDelegatorFee(address validator) external override {
        // claim rewards in the redelegate mode (check function code for more info)
        _redelegateDelegatorRewards(validator, msg.sender, currentEpoch(), true, false);
    }

    function _safeTransferWithGasLimit(address payable recipient, uint256 amount) internal virtual {
        (bool success,) = recipient.call{value : amount, gas : TRANSFER_GAS_LIMIT}("");
        require(success);
    }

    function _unsafeTransfer(address payable recipient, uint256 amount) internal virtual {
        (bool success,) = payable(address(recipient)).call{value : amount}("");
        require(success);
    }

    function slash(address validatorAddress) external onlyFromSlashingIndicator virtual override {
        _slashValidator(validatorAddress);
    }

    function _slashValidator(address validatorAddress) internal {
        // make sure validator exists
        StakingLibrary.Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.status != StakingLibrary.ValidatorStatus.NotFound, "not found");
        uint64 epoch = currentEpoch();
        // increase slashes for current epoch
        StakingLibrary.ValidatorSnapshot storage currentSnapshot = StakingLibrary.touchValidatorSnapshot(_validatorSnapshots, validator, epoch);
        uint32 slashesCount = currentSnapshot.slashesCount + 1;
        currentSnapshot.slashesCount = slashesCount;
        // if validator has a lot of misses then put it in jail for 1 week (if epoch is 1 day)
        if (slashesCount == _CHAIN_CONFIG_CONTRACT.getFelonyThreshold()) {
            validator.jailedBefore = currentEpoch() + _CHAIN_CONFIG_CONTRACT.getValidatorJailEpochLength();
            validator.status = StakingLibrary.ValidatorStatus.Jail;
            _removeValidatorFromActiveList(validatorAddress);
            _validatorsMap[validatorAddress] = validator;
            emit ValidatorJailed(validatorAddress, epoch);
        } else {
            // validator state might change, lets update it
            _validatorsMap[validatorAddress] = validator;
        }
        // emit event
        emit ValidatorSlashed(validatorAddress, slashesCount, epoch);
    }
}
