/* @description Wrapper for SAP response messages.
 *              Normalizes the SAP Return.item structure to handle both
 *              single-object and array responses.
 *
 *              Handles SAP response messages containing:
 *              - Success messages
 *              - Warning messages
 *              - Error messages
 *
 *              Reserved Apex keywords used by SAP (Return, Number, System)
 *              are mapped to Apex-safe property names.
 */
public class RES_ResponseWrapper {

    public ReturnWrapper responseReturn;

    public class ReturnWrapper {
        public List<ItemWrapper> item;
    }

    public class ItemWrapper {
        public String type;
        public String id;
        public String messageNumber;
        public String message;
        public String logNo;
        public String logMsgNo;
        public String messageV1;
        public String messageV2;
        public String messageV3;
        public String messageV4;
        public String parameter;
        public String row;
        public String field;
        public String systemName;
    }

    public static RES_ResponseWrapper deserialize(String responseBody) {
        if (String.isBlank(responseBody)) {
            return null;
        }

        Map<String, Object> root =
            (Map<String, Object>) JSON.deserializeUntyped(responseBody);

        Map<String, Object> sapReturn =
            (Map<String, Object>) root.remove('Return');

        if (sapReturn == null) {
            return null;
        }

        Object item = sapReturn.get('item');
        List<Object> items = new List<Object>();

        if (item instanceof Map<String, Object>) {
            items.add(item);
        } else if (item instanceof List<Object>) {
            items = (List<Object>) item;
        }

        for (Object obj : items) {
            Map<String, Object> itemMap = (Map<String, Object>) obj;

            itemMap.put('messageNumber', itemMap.remove('Number'));
            itemMap.put('systemName', itemMap.remove('System'));
        }

        sapReturn.put('item', items);
        root.put('responseReturn', sapReturn);
        return (RES_ResponseWrapper) JSON.deserialize(
            JSON.serialize(root),
            RES_ResponseWrapper.class
        );
    }

    public static void logError(RES_IntegrationErrorLogger log){
        try{
            RES_IntegrationErrorLogger.log(log);
        }Catch(Exception e){
            System.debug('Error while logging Integration Log ' + e.getMessage());
        }
    }

}