@isTest
private class RES_ContractCreationResponseWrapperTest {

    // ─── helpers ─────────────────────────────────────────────────────────────

    private static String buildSuccessResponse() {
        return JSON.serialize(new Map<String, Object>{
            'n0:ZRE_SALES_CONTRACT_CREATIONResponse' => new Map<String, Object>{
                'ES_CONTRACT_CREATED' => new Map<String, Object>{
                    'COMP_CODE'       => '1000',
                    'CONTRACT_NUMBER' => '0000001200407',
                    'CONTRACT_TYPE'   => 'Y002',
                    'C4CREF'          => 'SF5531'
                },
                'ET_RETURN'   => '',
                'IT_PARTNERS' => new Map<String, Object>{
                    'item' => new Map<String, Object>{
                        'ROLE' => 'ZTR602', 'PARTNER' => '20001621'
                    }
                }
            }
        });
    }

    private static String buildErrorResponse() {
        return JSON.serialize(new Map<String, Object>{
            'n0:ZRE_SALES_CONTRACT_CREATIONResponse' => new Map<String, Object>{
                'ES_CONTRACT_CREATED' => new Map<String, Object>{
                    'COMP_CODE' => '', 'CONTRACT_NUMBER' => '',
                    'CONTRACT_TYPE' => '', 'C4CREF' => ''
                },
                'ET_RETURN' => new Map<String, Object>{
                    'item' => new Map<String, Object>{
                        'TYPE'    => 'E',
                        'ID'      => 'RECAAP',
                        'NUMBER'  => '061',
                        'MESSAGE' => 'Rental Object 1000/200/20001621 does not exist',
                        'System'  => 'S4DCLNT250'
                    }
                },
                'IT_PARTNERS' => new Map<String, Object>{
                    'item' => new Map<String, Object>{
                        'ROLE' => 'ZTR602', 'PARTNER' => 'EXTERNL_ACCOUNT'
                    }
                }
            }
        });
    }

    // ─── deserialize ─────────────────────────────────────────────────────────

    @isTest
    static void deserializeReturnsNullForBlankBody() {
        Assert.isNull(RES_ContractCreationResponseWrapper.deserialize(''), 'Blank body should return null.');
        Assert.isNull(RES_ContractCreationResponseWrapper.deserialize(null), 'Null body should return null.');
    }

    @isTest
    static void deserializeSuccessPopulatesContractFields() {
        RES_ContractCreationResponseWrapper result =
            RES_ContractCreationResponseWrapper.deserialize(buildSuccessResponse());

        Assert.isNotNull(result, 'Result should not be null for a valid success response.');
        Assert.areEqual('0000001200407', result.contractNumber, 'CONTRACT_NUMBER should be mapped.');
        Assert.areEqual('1000',          result.compCode,       'COMP_CODE should be mapped.');
        Assert.areEqual('Y002',          result.contractType,   'CONTRACT_TYPE should be mapped.');
        Assert.areEqual('SF5531',        result.c4cRef,         'C4CREF should be mapped.');
    }

    @isTest
    static void deserializeErrorPopulatesEmptyContractFields() {
        RES_ContractCreationResponseWrapper result =
            RES_ContractCreationResponseWrapper.deserialize(buildErrorResponse());

        Assert.isNotNull(result, 'Result should not be null for an error response.');
        Assert.isNull(result.contractNumber, 'CONTRACT_NUMBER should be null when blank in error response.');
    }

    @isTest
    static void deserializeHandlesResponseWithoutEnvelopeKey() {
        // Response body with no ZRE_SALES_CONTRACT_CREATIONResponse wrapper
        String body = JSON.serialize(new Map<String, Object>{
            'ES_CONTRACT_CREATED' => new Map<String, Object>{
                'CONTRACT_NUMBER' => '9999', 'COMP_CODE' => '2000',
                'CONTRACT_TYPE' => 'Y001', 'C4CREF' => 'SF0001'
            },
            'ET_RETURN' => ''
        });
        RES_ContractCreationResponseWrapper result =
            RES_ContractCreationResponseWrapper.deserialize(body);

        Assert.isNotNull(result, 'Should handle unwrapped response body gracefully.');
        Assert.areEqual('9999', result.contractNumber, 'CONTRACT_NUMBER should be mapped without envelope.');
    }

    // ─── hasErrors ───────────────────────────────────────────────────────────

    @isTest
    static void hasErrorsReturnsFalseForSuccessResponse() {
        RES_ContractCreationResponseWrapper result =
            RES_ContractCreationResponseWrapper.deserialize(buildSuccessResponse());

        Assert.isFalse(result.hasErrors(), 'hasErrors should be false when ET_RETURN is empty.');
    }

    @isTest
    static void hasErrorsReturnsTrueForErrorResponse() {
        RES_ContractCreationResponseWrapper result =
            RES_ContractCreationResponseWrapper.deserialize(buildErrorResponse());

        Assert.isTrue(result.hasErrors(), 'hasErrors should be true when ET_RETURN contains type E item.');
    }

    @isTest
    static void hasErrorsReturnsFalseWhenResponseWrapperIsNull() {
        RES_ContractCreationResponseWrapper wrapper = new RES_ContractCreationResponseWrapper();
        wrapper.responseWrapper = null;
        Assert.isFalse(wrapper.hasErrors(), 'hasErrors should be false when responseWrapper is null.');
    }

    // ─── getErrorMessage ─────────────────────────────────────────────────────

    @isTest
    static void getErrorMessageReturnsBlankForSuccessResponse() {
        RES_ContractCreationResponseWrapper result =
            RES_ContractCreationResponseWrapper.deserialize(buildSuccessResponse());

        Assert.areEqual('', result.getErrorMessage(), 'Error message should be blank for a success response.');
    }

    @isTest
    static void getErrorMessageReturnsMessageFromErrorResponse() {
        RES_ContractCreationResponseWrapper result =
            RES_ContractCreationResponseWrapper.deserialize(buildErrorResponse());

        Assert.isTrue(
            result.getErrorMessage().contains('Rental Object'),
            'Error message should contain the SAP error text.'
        );
    }

    @isTest
    static void getErrorMessageReturnsBlankWhenResponseWrapperIsNull() {
        RES_ContractCreationResponseWrapper wrapper = new RES_ContractCreationResponseWrapper();
        wrapper.responseWrapper = null;
        Assert.areEqual('', wrapper.getErrorMessage(), 'getErrorMessage should return blank when responseWrapper is null.');
    }

    // ─── isSuccess ───────────────────────────────────────────────────────────

    @isTest
    static void isSuccessReturnsTrueForSuccessResponse() {
        RES_ContractCreationResponseWrapper result =
            RES_ContractCreationResponseWrapper.deserialize(buildSuccessResponse());

        Assert.isTrue(result.isSuccess(), 'isSuccess should be true when no errors and contractNumber is present.');
    }

    @isTest
    static void isSuccessReturnsFalseForErrorResponse() {
        RES_ContractCreationResponseWrapper result =
            RES_ContractCreationResponseWrapper.deserialize(buildErrorResponse());

        Assert.isFalse(result.isSuccess(), 'isSuccess should be false when ET_RETURN has error items.');
    }

    @isTest
    static void isSuccessReturnsFalseWhenContractNumberIsBlank() {
        RES_ContractCreationResponseWrapper wrapper = new RES_ContractCreationResponseWrapper();
        wrapper.contractNumber  = null;
        wrapper.responseWrapper = null;
        Assert.isFalse(wrapper.isSuccess(), 'isSuccess should be false when contractNumber is null.');
    }
}
