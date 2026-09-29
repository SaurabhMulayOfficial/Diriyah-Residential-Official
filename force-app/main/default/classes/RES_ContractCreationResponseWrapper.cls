/**
 * @description Deserializes the SAP ZRE_SALES_CONTRACT_CREATION response envelope.
 *
 * Handles both the success shape:
 *   ES_CONTRACT_CREATED: { CONTRACT_NUMBER, COMP_CODE, CONTRACT_TYPE, C4CREF }
 *   ET_RETURN: ""
 *
 * and the error shape:
 *   ES_CONTRACT_CREATED: { CONTRACT_NUMBER: "", ... }
 *   ET_RETURN: { item: { TYPE: "E", MESSAGE: "...", ... } }
 *
 * ET_RETURN error items are normalised via RES_ResponseWrapper.
 */
public class RES_ContractCreationResponseWrapper {

    public String contractNumber;
    public String compCode;
    public String contractType;
    public String c4cRef;
    public RES_ResponseWrapper responseWrapper;

    public static RES_ContractCreationResponseWrapper deserialize(String responseBody) {
        if (String.isBlank(responseBody)) {
            return null;
        }

        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(responseBody);

        // Unwrap the SOAP envelope key (e.g. "n0:ZRE_SALES_CONTRACT_CREATIONResponse")
        for (String key : root.keySet()) {
            if (key.contains('ZRE_SALES_CONTRACT_CREATIONResponse')) {
                root = (Map<String, Object>) root.get(key);
                break;
            }
        }

        RES_ContractCreationResponseWrapper result = new RES_ContractCreationResponseWrapper();

        Object esCreated = root.get('ES_CONTRACT_CREATED');
        if (esCreated instanceof Map<String, Object>) {
            Map<String, Object> esMap = (Map<String, Object>) esCreated;
            result.contractNumber = getString(esMap, 'CONTRACT_NUMBER');
            result.compCode       = getString(esMap, 'COMP_CODE');
            result.contractType   = getString(esMap, 'CONTRACT_TYPE');
            result.c4cRef         = getString(esMap, 'C4CREF');
        }

        // Remove ET_RETURN if it is an empty string so RES_ResponseWrapper.deserialize
        // does not attempt to cast "" to Map<String,Object> and throw a TypeException.
        Object etReturn = root.get('ET_RETURN');
        if (etReturn instanceof String) {
            root.remove('ET_RETURN');
        }

        // Delegate ET_RETURN parsing to RES_ResponseWrapper
        result.responseWrapper = RES_ResponseWrapper.deserialize(JSON.serialize(root));

        return result;
    }

    public Boolean hasErrors() {
        if (responseWrapper == null ||
            responseWrapper.responseReturn == null ||
            responseWrapper.responseReturn.item == null) {
            return false;
        }
        for (RES_ResponseWrapper.ItemWrapper item : responseWrapper.responseReturn.item) {
            if (item.type == 'E') {
                return true;
            }
        }
        return false;
    }

    public String getErrorMessage() {
        if (responseWrapper == null ||
            responseWrapper.responseReturn == null ||
            responseWrapper.responseReturn.item == null) {
            return '';
        }
        String msg = '';
        for (RES_ResponseWrapper.ItemWrapper item : responseWrapper.responseReturn.item) {
            if (item.type == 'E' && String.isNotBlank(item.message)) {
                msg += item.message + ' ';
            }
        }
        return msg.trim();
    }

    public Boolean isSuccess() {
        return !hasErrors() && String.isNotBlank(contractNumber);
    }

    private static String getString(Map<String, Object> m, String key) {
        Object val = m.get(key);
        return (val != null && String.isNotBlank(String.valueOf(val))) ? String.valueOf(val) : null;
    }
}
