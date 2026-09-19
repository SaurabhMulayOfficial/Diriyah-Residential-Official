/** Abstraction over Context.IndustriesContext so pricing-hook logic can be unit tested against a fake implementation. */
public interface RES_IndustriesContextProvider {
    Map<String, Object> queryTags(Map<String, Object> queryInput);
    Object updateContextAttributes(Map<String, Object> updateInput);
}
