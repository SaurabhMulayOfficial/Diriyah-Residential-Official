/**
 * @description Wrapper for Sales Contract Creation integration request.
 *              Represents the SAP inbound JSON payload for CONTRACT_CREATION.
 * @author Saurabh Mulay
 */
public class RES_ContractCreationWrapper {

    public ContractCreationPayload CONTRACT_CREATION;

    public class ContractCreationPayload {
        public List<PartnerWrapper> IT_PARTNERS;
        public String IV_C4CREF;
        public String IV_C4CUSR;
        public String IV_CN_STDATE;
        public String IV_CN_ENDDATE;
        public String IV_CONTRACT_OBJECT_ID;
        public String IV_PAYPLAN_ID;
        public String IV_RECNTXT;
        public String IV_RECNTYPE;
        public String IV_FIRST_TIME_BUYER;
        public String IV_UNIT_PRICE;
        public String IV_CONTRACT_CONCLUSION_DATE;
        public String IV_RECNTXTOLD;
    }

    public class PartnerWrapper {
        public String ROLE;
        public String PARTNER;
    }
}
