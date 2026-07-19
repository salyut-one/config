#define PAM_SM_SESSION

#include <stddef.h>
#include <security/pam_appl.h>
#include <security/pam_modules.h>

/*
 * SSHD supplies its client address as PAM_RHOST. pam_systemd consumes that
 * item and exposes it as RemoteHost on the system bus, readable by ordinary
 * local users through loginctl. Clear the item immediately before the
 * password-auth stack invokes pam_systemd, while sshd continues to retain the
 * source address in its privileged journal and audit records.
 */
PAM_EXTERN int pam_sm_open_session(pam_handle_t *pamh, int flags,
                                   int argc, const char **argv)
{
    (void)flags;
    (void)argc;
    (void)argv;

    return pam_set_item(pamh, PAM_RHOST, NULL);
}

PAM_EXTERN int pam_sm_close_session(pam_handle_t *pamh, int flags,
                                    int argc, const char **argv)
{
    (void)pamh;
    (void)flags;
    (void)argc;
    (void)argv;

    return PAM_SUCCESS;
}
