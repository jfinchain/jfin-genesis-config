// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./InjectorContextHolder.sol";

contract ChainConfig is InjectorContextHolder, IChainConfig {

    event ActiveValidatorsLengthChanged(uint32 prevValue, uint32 newValue);
    event EpochBlockIntervalChanged(uint32 prevValue, uint32 newValue);
    event MisdemeanorThresholdChanged(uint32 prevValue, uint32 newValue);
    event FelonyThresholdChanged(uint32 prevValue, uint32 newValue);
    event ValidatorJailEpochLengthChanged(uint32 prevValue, uint32 newValue);
    event UndelegatePeriodChanged(uint32 prevValue, uint32 newValue);
    event MinValidatorStakeAmountChanged(uint256 prevValue, uint256 newValue);
    event MinStakingAmountChanged(uint256 prevValue, uint256 newValue);
    event MinTotalDelegatedAmountChanged(uint256 prevValue, uint256 newValue);
    event JdnWalletAddressChanged(address prevValue, address newValue);
    event VatWalletAddressChanged(address prevValue, address newValue);
    event WhtWalletAddressChanged(address prevValue, address newValue);

    // 10000 = 100%
    uint32 constant public PERCENT_PRECISION = 10000;

    struct ConsensusParams {
        uint32 activeValidatorsLength;
        uint32 epochBlockInterval;
        uint32 misdemeanorThreshold;
        uint32 felonyThreshold;
        uint32 validatorJailEpochLength;
        uint32 undelegatePeriod;
        uint256 minValidatorStakeAmount;
        uint256 minStakingAmount;
        uint256 minTotalDelegatedAmount;
        address jdnWalletAddress;
        address vatWalletAddress;
        address whtWalletAddress;
        SplitPercent splitPercent;
        TaxPercent taxPercent;
    }

    ConsensusParams private _consensusParams;

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

    function initialize(
        uint32 activeValidatorsLength,
        uint32 epochBlockInterval,
        uint32 misdemeanorThreshold,
        uint32 felonyThreshold,
        uint32 validatorJailEpochLength,
        uint32 undelegatePeriod,
        uint256 minValidatorStakeAmount,
        uint256 minStakingAmount
    ) external initializer {
        _consensusParams.activeValidatorsLength = activeValidatorsLength;
        emit ActiveValidatorsLengthChanged(0, activeValidatorsLength);
        _consensusParams.epochBlockInterval = epochBlockInterval;
        emit EpochBlockIntervalChanged(0, epochBlockInterval);
        _consensusParams.misdemeanorThreshold = misdemeanorThreshold;
        emit MisdemeanorThresholdChanged(0, misdemeanorThreshold);
        _consensusParams.felonyThreshold = felonyThreshold;
        emit FelonyThresholdChanged(0, felonyThreshold);
        _consensusParams.validatorJailEpochLength = validatorJailEpochLength;
        emit ValidatorJailEpochLengthChanged(0, validatorJailEpochLength);
        _consensusParams.undelegatePeriod = undelegatePeriod;
        emit UndelegatePeriodChanged(0, undelegatePeriod);
        _consensusParams.minValidatorStakeAmount = minValidatorStakeAmount;
        emit MinValidatorStakeAmountChanged(0, minValidatorStakeAmount);
        _consensusParams.minStakingAmount = minStakingAmount;
        emit MinStakingAmountChanged(0, minStakingAmount);
        _consensusParams.jdnWalletAddress = 0x5266Dfa5ae013674f8FdC832b7c601B838D94eE6; // hw1
        emit JdnWalletAddressChanged(0x0000000000000000000000000000000000000000, 0x5266Dfa5ae013674f8FdC832b7c601B838D94eE6);
        _consensusParams.vatWalletAddress = 0xC3317062E170f5794825dC5D93D6b045f06Bf3a5; // hw2
        emit VatWalletAddressChanged(0x0000000000000000000000000000000000000000, 0xC3317062E170f5794825dC5D93D6b045f06Bf3a5);
        _consensusParams.whtWalletAddress = 0xAC5675D47B1Cd43C836dF6014D86B70B06173542; // hw3
        emit WhtWalletAddressChanged(0x0000000000000000000000000000000000000000, 0xAC5675D47B1Cd43C836dF6014D86B70B06173542);
        _consensusParams.minTotalDelegatedAmount = 1000000000000000000000000;
        _consensusParams.splitPercent = SplitPercent(3300, 670, 6030); // 33%, 6.7%, 60.3%
        _consensusParams.taxPercent = TaxPercent(654, 300, 1500); // 7%, 3%, 15%
    }

    function getActiveValidatorsLength() external view override returns (uint32) {
        return _consensusParams.activeValidatorsLength;
    }

    function setActiveValidatorsLength(uint32 newValue) external override onlyFromGovernance {
        uint32 prevValue = _consensusParams.activeValidatorsLength;
        _consensusParams.activeValidatorsLength = newValue;
        emit ActiveValidatorsLengthChanged(prevValue, newValue);
    }

    function getEpochBlockInterval() external view override returns (uint32) {
        return _consensusParams.epochBlockInterval;
    }

    function setEpochBlockInterval(uint32 newValue) external override onlyFromGovernance {
        uint32 prevValue = _consensusParams.epochBlockInterval;
        _consensusParams.epochBlockInterval = newValue;
        emit EpochBlockIntervalChanged(prevValue, newValue);
    }

    function getMisdemeanorThreshold() external view override returns (uint32) {
        return _consensusParams.misdemeanorThreshold;
    }

    function setMisdemeanorThreshold(uint32 newValue) external override onlyFromGovernance {
        uint32 prevValue = _consensusParams.misdemeanorThreshold;
        _consensusParams.misdemeanorThreshold = newValue;
        emit MisdemeanorThresholdChanged(prevValue, newValue);
    }

    function getFelonyThreshold() external view override returns (uint32) {
        return _consensusParams.felonyThreshold;
    }

    function setFelonyThreshold(uint32 newValue) external override onlyFromGovernance {
        uint32 prevValue = _consensusParams.felonyThreshold;
        _consensusParams.felonyThreshold = newValue;
        emit FelonyThresholdChanged(prevValue, newValue);
    }

    function getValidatorJailEpochLength() external view override returns (uint32) {
        return _consensusParams.validatorJailEpochLength;
    }

    function setValidatorJailEpochLength(uint32 newValue) external override onlyFromGovernance {
        uint32 prevValue = _consensusParams.validatorJailEpochLength;
        _consensusParams.validatorJailEpochLength = newValue;
        emit ValidatorJailEpochLengthChanged(prevValue, newValue);
    }

    function getUndelegatePeriod() external view override returns (uint32) {
        return _consensusParams.undelegatePeriod;
    }

    function setUndelegatePeriod(uint32 newValue) external override onlyFromGovernance {
        uint32 prevValue = _consensusParams.undelegatePeriod;
        _consensusParams.undelegatePeriod = newValue;
        emit UndelegatePeriodChanged(prevValue, newValue);
    }

    function getMinValidatorStakeAmount() external view returns (uint256) {
        return _consensusParams.minValidatorStakeAmount;
    }

    function setMinValidatorStakeAmount(uint256 newValue) external override onlyFromGovernance {
        uint256 prevValue = _consensusParams.minValidatorStakeAmount;
        _consensusParams.minValidatorStakeAmount = newValue;
        emit MinValidatorStakeAmountChanged(prevValue, newValue);
    }

    function getMinStakingAmount() external view returns (uint256) {
        return _consensusParams.minStakingAmount;
    }

    function setMinStakingAmount(uint256 newValue) external override onlyFromGovernance {
        uint256 prevValue = _consensusParams.minStakingAmount;
        _consensusParams.minStakingAmount = newValue;
        emit MinStakingAmountChanged(prevValue, newValue);
    }

    function getMinTotalDelegatedAmount() external view returns (uint256) {
        return _consensusParams.minTotalDelegatedAmount;
    }

    function setMinTotalDelegatedAmount(uint256 newValue) external override onlyFromGovernance {
        uint256 prevValue = _consensusParams.minTotalDelegatedAmount;
        _consensusParams.minTotalDelegatedAmount = newValue;
        emit MinTotalDelegatedAmountChanged(prevValue, newValue);
    }

    function getJdnWalletAddress() external view returns (address) {
        return _consensusParams.jdnWalletAddress;
    }

    function setJdnWalletAddress(address newValue) external override onlyFromGovernance {
        address prevValue = _consensusParams.jdnWalletAddress;
        _consensusParams.jdnWalletAddress = newValue;
        emit JdnWalletAddressChanged(prevValue, newValue);
    }

    function getVatWalletAddress() external view returns (address) {
        return _consensusParams.vatWalletAddress;
    }

    function setVatWalletAddress(address newValue) external override onlyFromGovernance {
        address prevValue = _consensusParams.vatWalletAddress;
        _consensusParams.vatWalletAddress = newValue;
        emit VatWalletAddressChanged(prevValue, newValue);
    }

    function getWhtWalletAddress() external view returns (address) {
        return _consensusParams.whtWalletAddress;
    }

    function setWhtWalletAddress(address newValue) external override onlyFromGovernance {
        address prevValue = _consensusParams.whtWalletAddress;
        _consensusParams.whtWalletAddress = newValue;
        emit WhtWalletAddressChanged(prevValue, newValue);
    }

    function getSplitPercent() external view returns (SplitPercent memory) {
        return _consensusParams.splitPercent;
    }

    function setSplitPercent(SplitPercent memory newValue) external override onlyFromGovernance {
        require(newValue.jdn + newValue.validator + newValue.stakers == PERCENT_PRECISION, "ChainConfig: invalid percent");
        _consensusParams.splitPercent = newValue;
    }

    function getTaxPercent() external view returns (TaxPercent memory) {
        return _consensusParams.taxPercent;
    }

    function setTaxPercent(TaxPercent memory newValue) external override onlyFromGovernance {
        require(newValue.vat <= PERCENT_PRECISION, "ChainConfig: invalid percent");
        require(newValue.whtCompany <= PERCENT_PRECISION, "ChainConfig: invalid percent");
        require(newValue.whtIndividual <= PERCENT_PRECISION, "ChainConfig: invalid percent");
        _consensusParams.taxPercent = newValue;
    }

    function getPercentPrecision() external pure returns (uint32) {
        return PERCENT_PRECISION;
    }
}