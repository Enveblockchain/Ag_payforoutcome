// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol";


contract AccuweatherConsumer is ChainlinkClient {
    using Chainlink for Chainlink.Request;
    using SafeMath for uint;

    /* ========== CONSUMER STATE VARIABLES ========== */
    uint constant public outcome_Payment = 0.1 ether;
    uint24 public precip24;
    address payable constant Financier = payable(0x807bd238edB3aa7eaeDbDcC324c690dcf6301e60);
    address payable constant ServiceProv = payable(0x06645472cD9e2843fb3e2C97dCe5863857F73F77);
    address payable constant Gov = payable(0x9278D4F1AE185F3B05f6Ca9a6Ee754685ee2c161);
    bytes32 public loccurcondition_RID;
    bytes32 private loccurcondition_jobId;

    struct RequestParams {
        uint256 locationKey;
        string endpoint;
        string lat;
        string lon;
        string units;
    }
    struct LocationResult {
        uint256 locationKey;
        string name;
        bytes2 countryCode;
    }
    struct CurrentConditionsResult {
        uint256 timestamp;
        uint24 precipitationPast12Hours;
        uint24 precipitationPast24Hours;
        uint24 precipitationPastHour;
        uint24 pressure;
        int16 temperature;
        uint16 windDirectionDegrees;
        uint16 windSpeed;
        uint8 precipitationType;
        uint8 relativeHumidity;
        uint8 uvIndex;
        uint8 weatherIcon;
    }

    struct benefitPayment {
        uint allowanceAmount;
        uint allowancePeriodInDays;
        uint whenLastAllowance;
        uint unspentAllowance;
    }

    mapping(address => benefitPayment) public payouts;

    // Maps
    mapping(bytes32 => RequestParams) public requestIdRequestParams;
    mapping(bytes32 => LocationResult) public requestIdLocationResult;
    mapping(bytes32 => CurrentConditionsResult) public requestIdCurrentConditionsResult;


    /* ========== Enable smart contract payments and withdrawals ========== */
    receive () external payable {
    }

    //gives farmer the ability to withdraw money saved in the smart contract.
    //_amount is in WEI not ETH or GWEI
    //there are different functions that to similar things as .transfer()
    //but .transfer() seems to be the best way at the time of this writing.

    function withdrawFromContractBalance(address payable _addr, uint _amount) public {
        require(address(this).balance >= _amount, "Contract balance too low to fund withdraw");
        _addr.transfer(_amount);
    }
    
    //Beneficiaries make payments
    function addBenefitPayment(address _addr, uint _paymentAmount, uint _paymentPeriodInDays) public {
        require(payouts[_addr].allowanceAmount == 0, "Allowance already exists");
        require(address(this).balance >= _paymentAmount, "Contract balance too low to make payment");
        // Initialize new payouts
        benefitPayment memory payout;
        payout.allowanceAmount = _paymentAmount;
        payout.allowancePeriodInDays = _paymentPeriodInDays.mul(1 days);
        payout.whenLastAllowance = block.timestamp;
        payout.unspentAllowance = _paymentAmount;
        
        payouts[_addr] = payout;
    }

    //Financiers withdraw from benefitPayment struct
    function getBenefitPayment (uint _amount) public {
        require(payouts[msg.sender].allowanceAmount > 0, "You're not a recipient of an allowance");
        require(address(this).balance >= _amount, "Contract balance too low to pay allowance");
        // Calculate and update unspent allowance
        uint numAllowances = block.timestamp.sub(payouts[msg.sender].whenLastAllowance).div(payouts[msg.sender].allowancePeriodInDays);
        payouts[msg.sender].unspentAllowance = payouts[msg.sender].allowanceAmount.mul(numAllowances).add(payouts[msg.sender].unspentAllowance);
        payouts[msg.sender].whenLastAllowance = numAllowances.mul(1 days).add(payouts[msg.sender].whenLastAllowance);
        
        // Pay allowance
        require(payouts[msg.sender].unspentAllowance >= _amount, "You asked for more allowance than you're owed'");
        payable(msg.sender).transfer(_amount);
        payouts[msg.sender].unspentAllowance = payouts[msg.sender].unspentAllowance.sub(_amount);
    }





    /* ========== CONSTRUCTOR ========== */

    /**
     * @param _link the LINK token address.
     * @param _oracle the Operator.sol contract address.
     *Kovan testnet _link address: 0xa36085F69e2889c224210F603D836748e7dC0088
     *Kovan testnet _oracle address: 0xfF07C97631Ff3bAb5e5e5660Cdf47AdEd8D4d4Fd
     */
    constructor(address _link, address _oracle) {
        setChainlinkToken(_link);
        setChainlinkOracle(_oracle);
        loccurcondition_jobId = "7c276986e23b4b1c990d8659bca7a9d0";
    }

    /* ========== CONSUMER REQUEST FUNCTIONS ========== */

      function requestLocationCurrentConditions(uint256 _payment, string calldata _lat, string calldata _lon, string calldata _units) public {
        Chainlink.Request memory req = buildChainlinkRequest(loccurcondition_jobId, address(this), this.fulfillLocationCurrentConditions.selector);

        req.add("endpoint", "location-current-conditions"); // NB: not required if it has been hardcoded in the job spec
        req.add("lat", _lat);
        req.add("lon", _lon);
        req.add("units", _units);

        bytes32 requestId = sendChainlinkRequest(req, _payment);

        // Below this line is just an example of usage
        //storeRequestParams(requestId, 0, "location-current-conditions", _lat, _lon, _units);
    }

    /* ========== CONSUMER FULFILL FUNCTIONS ========== */
    
    function fulfillLocationCurrentConditions(bytes32 _requestId, bool _locationFound, bytes memory _locationResult, bytes memory _currentConditionsResult) public recordChainlinkFulfillment(_requestId) {
        loccurcondition_RID = _requestId;
        if (_locationFound) {
            storeLocationResult(_requestId, _locationResult);
            storeCurrentConditionsResult(_requestId, _currentConditionsResult);
        }
    }

    function outcomePayment() public {
        if (precip24 <= 150) {
            getBenefitPayment (outcome_Payment);

        }
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function storeRequestParams(bytes32 _requestId, uint256 _locationKey, string memory _endpoint, string memory _lat, string memory _lon, string memory _units) private {
        RequestParams memory requestParams;
        requestParams.locationKey = _locationKey;
        requestParams.endpoint = _endpoint;
        requestParams.lat = _lat;
        requestParams.lon = _lon;
        requestParams.units = _units;
        requestIdRequestParams[_requestId] = requestParams;
    }

    function storeLocationResult(bytes32 _requestId, bytes memory _locationResult) private {
        LocationResult memory result = abi.decode(_locationResult, (LocationResult));
        requestIdLocationResult[_requestId] = result;
    }

    function storeCurrentConditionsResult(bytes32 _requestId, bytes memory _currentConditionsResult) private {
        CurrentConditionsResult memory result = abi.decode(_currentConditionsResult, (CurrentConditionsResult));
        requestIdCurrentConditionsResult[_requestId] = result;
        precip24 = result.precipitationPast24Hours;
    }

    /* ========== OTHER FUNCTIONS ========== */

    function getOracleAddress() external view returns (address) {
        return chainlinkOracleAddress();
    }

    function setOracle(address _oracle) external {
        setChainlinkOracle(_oracle);
    }

    function withdrawLink() public {
        LinkTokenInterface linkToken = LinkTokenInterface(chainlinkTokenAddress());
        require(linkToken.transfer(msg.sender, linkToken.balanceOf(address(this))), "Unable to transfer");
    }
}
