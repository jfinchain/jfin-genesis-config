// Root file: contracts/interfaces/IChainConfig.sol

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

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