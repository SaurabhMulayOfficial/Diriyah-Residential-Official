/** Test-only fake provider returning fabricated queryTags/updateContextAttributes results for unit tests. */
@isTest
public class RES_FakeIndustriesContextProvider implements RES_IndustriesContextProvider {
    public Map<String, Object> queryTagsInput;
    public Map<String, Object> queryTagsResultToReturn = new Map<String, Object>();
    public Boolean throwOnQueryTags = false;

    public Map<String, Object> updateContextAttributesInput;
    public Object updateContextAttributesResultToReturn;
    public Integer updateContextAttributesCallCount = 0;

    public Map<String, Object> queryTags(Map<String, Object> queryInput) {
        this.queryTagsInput = queryInput;
        if (throwOnQueryTags) {
            throw new System.NullPointerException();
        }
        return queryTagsResultToReturn;
    }

    public Object updateContextAttributes(Map<String, Object> updateInput) {
        this.updateContextAttributesInput = updateInput;
        this.updateContextAttributesCallCount++;
        return updateContextAttributesResultToReturn;
    }

    /** Builds a fake queryResult wrapper matching the {queryResult: {tagName: [...]}} shape the hook parses. */
    public static Map<String, Object> wrapQueryResult(String tagName, List<Object> items) {
        return new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                tagName => items
            }
        };
    }

    /** Builds one fake SalesTransactionItem node; dmlStatus, if given, attaches to the LineItemPath tag. */
    public static Map<String, Object> buildLineItemNode(
        String lineItemId, String lineItemPath, String productId, List<Object> dataPath, String dmlStatus
    ) {
        Map<String, Object> lineItemPathTag = new Map<String, Object>{'tagValue' => lineItemPath};
        if (dmlStatus != null) {
            lineItemPathTag.put('dmlStatus', dmlStatus);
        }
        return new Map<String, Object>{
            'tagValue' => new Map<String, Object>{
                'LineItem' => new Map<String, Object>{'tagValue' => lineItemId},
                'LineItemPath' => lineItemPathTag,
                'Product' => new Map<String, Object>{'tagValue' => productId}
            },
            'dataPath' => dataPath
        };
    }

    /** Builds one fake SalesTransactionItemAttribute node. */
    public static Map<String, Object> buildAttributeNode(
        String parentItemId, String attributeName, String attributeValue, List<Object> dataPath
    ) {
        return new Map<String, Object>{
            'tagValue' => new Map<String, Object>{
                'SalesTransactionItemAttrParent' => new Map<String, Object>{'tagValue' => parentItemId},
                'Attribute' => new Map<String, Object>{'tagValue' => attributeName},
                'AttributeValue' => new Map<String, Object>{'tagValue' => attributeValue}
            },
            'dataPath' => dataPath
        };
    }
}
