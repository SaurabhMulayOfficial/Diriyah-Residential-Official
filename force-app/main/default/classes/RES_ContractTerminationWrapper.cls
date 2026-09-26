/**
 * @description Wrapper for Sales Contract Termination integration request.
 *              Represents the SAP inbound JSON payload for CONTRACT_TERM.
 * @author Saurabh Mulay
 */
public class RES_ContractTerminationWrapper {

    public ContractTerminationPayload CONTRACT_TERM;

    public class ContractTerminationPayload {
        public String  IV_COMPANY_CODE;
        public String  IV_CONTRACT;
        public String  IV_ENTRY_DATE;
        public String  IV_REQUESTED_DATE;
        public String  IV_FINAL_TERMINATION_DATE;
        public String  IV_CONTRACT_STATUS;
        public String  IV_TERMINATION_REASON;
        public String  IV_NOTE;
        public String  IV_C4CUSR;
        public String  IV_CONTRACT_OBJECT_ID;
        public String  UNIT_STATUS;
    }
}
