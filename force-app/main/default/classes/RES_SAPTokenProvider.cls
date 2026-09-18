public without sharing class RES_SAPTokenProvider extends RES_BaseIntegrationCalloutService {
    public static String SAP_TOKEN = '';
    public RES_SAPTokenProvider() {
        Super();
        setEndpoint('Callout:SAPToken');
        setRequestMethod('POST');
        setRequestName('SAP Token Request');
        setMaxRetries(3);
        setTimeout(10000);
        setBody('');
    }

    public String getToken(){
        if(String.isBlank(SAP_TOKEN)){
            RES_SAPTokenProvider tokenProvider = new RES_SAPTokenProvider();
            RES_IntegrationResponse response = tokenProvider.sendRequest();
            System.debug('SAP Token Response: ' + response.responseBody);
            try{
                if(response.statusCode >= 200 && response.statusCode < 300){
                    Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(response.responseBody);
                    SAP_TOKEN = (String) responseMap.get('access_token');
                } else {
                    System.debug('Error getting SAP token: ' + response.responseBody);

                }
            }catch(Exception e){
                System.debug('Exception while extracting SAP token: ' + e.getMessage());
            }
        }
        return SAP_TOKEN;
    }
}