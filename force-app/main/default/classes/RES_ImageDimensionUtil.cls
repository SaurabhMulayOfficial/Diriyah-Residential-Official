// Reads width/height of PNG, JPEG or GIF files from the image header bytes.
public with sharing class RES_ImageDimensionUtil {

    // Accepts a ContentVersion Id (068) or ContentDocument Id (069, uses latest version); returns {width, height} or null.
    public static Map<String, Integer> getDimensions(Id fileId) {
        List<ContentVersion> cvs = String.valueOf(fileId).startsWith('069')
            ? [SELECT VersionData FROM ContentVersion WHERE ContentDocumentId = :fileId AND IsLatest = true LIMIT 1]
            : [SELECT VersionData FROM ContentVersion WHERE Id = :fileId LIMIT 1];
        return cvs.isEmpty() ? null : getDimensions(cvs[0].VersionData);
    }

    public static Map<String, Integer> getDimensions(Blob data) {
        if (data == null) return null;
        String h = EncodingUtil.convertToHex(data);
        if (h.startsWith('89504e47') && h.length() >= 48) {          // PNG: IHDR big-endian at bytes 16-23
            return result(be(h, 16, 4), be(h, 20, 4));
        }
        if (h.startsWith('47494638') && h.length() >= 20) {          // GIF: little-endian at bytes 6-9
            return result(le16(h, 6), le16(h, 8));
        }
        if (h.startsWith('ffd8')) {                                  // JPEG: walk segments to the SOF marker
            Integer n = h.length() / 2;
            Integer i = 2;
            while (i + 9 < n) {
                if (byteAt(h, i) != 255) { i++; continue; }
                Integer m = byteAt(h, i + 1);
                if (m == 255) { i++; continue; }                     // fill byte
                if ((m >= 208 && m <= 215) || m == 1) { i += 2; continue; } // RSTn / TEM have no length
                if (m >= 192 && m <= 207 && m != 196 && m != 200 && m != 204) {
                    return result(be(h, i + 7, 2), be(h, i + 5, 2));
                }
                if (m == 218) break;                                 // SOS reached without SOF
                i += 2 + be(h, i + 2, 2);
            }
        }
        return null;
    }

    private static Map<String, Integer> result(Integer w, Integer ht) {
        return new Map<String, Integer>{ 'width' => w, 'height' => ht };
    }

    private static Integer byteAt(String h, Integer off) {
        return '0123456789abcdef'.indexOf(h.substring(off * 2, off * 2 + 1)) * 16
             + '0123456789abcdef'.indexOf(h.substring(off * 2 + 1, off * 2 + 2));
    }

    private static Integer be(String h, Integer off, Integer len) {
        Long v = 0;
        for (Integer k = 0; k < len; k++) v = v * 256 + byteAt(h, off + k);
        return v.intValue();
    }

    private static Integer le16(String h, Integer off) {
        return byteAt(h, off) + byteAt(h, off + 1) * 256;
    }
}
