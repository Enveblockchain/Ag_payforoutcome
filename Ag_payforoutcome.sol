// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol";


contract SoilandWater is ChainlinkClient {
    using Chainlink for Chainlink.Request;
    using SafeMath for uint;


    uint constant public outcome_Payment = 0.1 ether;
    uint24 public precip24;
    address payable constant Financier = payable(0x807bd238edB3aa7eaeDbDcC324c690dcf6301e60);
    address payable constant ServiceProv = payable(0x06645472cD9e2843fb3e2C97dCe5863857F73F77);
    address payable constant Gov = payable(0x9278D4F1AE185F3B05f6Ca9a6Ee754685ee2c161);
    bytes32 public loccurcondition_RID;
    bytes32 public loccurcondition_jobId;

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

    mapping(bytes32 => RequestParams) public requestIdRequestParams;
    mapping(bytes32 => LocationResult) public requestIdLocationResult;
    mapping(bytes32 => CurrentConditionsResult) public requestIdCurrentConditionsResult;


    /* ========== Enable smart contract payments and withdrawals ========== */
    receive () external payable {
    }

    function withdrawFromContractBalance(address payable _addr, uint _amount) public {
        require(address(this).balance >= _amount, "Contract balance too low to fund withdraw");
        _addr.transfer(_amount);
    }

    /* ========== CONSTRUCTOR ========== */

    /**
     * Goerli testnet _link address: 0x326C977E6efc84E512bB9C30f76E30c160eD06FB
     * Goerli testnet _oracle address: 0x7ecFBD6CB2D3927Aa68B5F2f477737172F11190a
     */
    constructor(address _link, address _oracle) {
        setChainlinkToken(_link);
        setChainlinkOracle(_oracle);
        loccurcondition_jobId = "eb894ae815a14257b6682ddff0913e1b";
    }

    /* ========== CONSUMER REQUEST FUNCTIONS ========== */

     //Example: Dubuque County 42.46916479 -90.873663172 from https://latitude.to/articles-by-country/us/united-states/33399/dubuque-county-iowa
     //_units: "metric"
    function requestLocationCurrentConditions(uint256 _payment, string calldata _lat, string calldata _lon, string calldata _units) public {
        Chainlink.Request memory req = buildChainlinkRequest(loccurcondition_jobId, address(this), this.fulfillLocationCurrentConditions.selector);

        req.add("endpoint", "location-current-conditions"); // NB: not required if it has been hardcoded in the job spec
        req.add("lat", _lat);
        req.add("lon", _lon);
        req.add("units", _units);

        bytes32 requestId = sendChainlinkRequest(req, _payment);
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
            withdrawFromContractBalance(Financier, outcome_Payment);

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
