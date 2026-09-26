/**
 * @description Wrapper for Sales Contract Update integration request.
 *              Represents the SAP inbound JSON payload for CONTRACT_UPDATE.
 * @author Saurabh Mulay
 */
public class RES_ContractUpdateWrapper {

    public ContractUpdatePayload CONTRACT_UPDATE;

    public class ContractUpdatePayload {
        public String IV_COMPANY_CODE;
        public String IV_CONTRACT;
        public String IV_CONTRACT_STATUS;
        public String IV_WF_TYPE;
        public String IV_C4C_USER;
        public String IV_NOTICE_DATE;
        public String IV_CN_OFFR;
        public String IV_RETAIL;
        public String IV_RESERVDATE;
        public Boolean IV_CT_FLAG;
        public Boolean TEST_RUN;
    }
}
