/++
+ Module for various low-level IRC connection details.
+/
module virc.connection;
/++
    TLS Modes. For better security, use as many flags as possible.
+/
enum TLSMode
{
    none, ///No TLS
    enabled = 1<<0, ///Basic TLS, ignore all certificate errors
    requireValidCert = 1<<1, ///Require at least a valid certificate, trustworthiness not checked
    requireMatchingName = 1<<2, ///Require the certificate to match the hostname
    requireTrust = 1<<3 ///Require the certificate to have a trustworthy certificate chain
}