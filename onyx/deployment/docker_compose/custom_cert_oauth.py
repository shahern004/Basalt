
from typing import Any, Optional, get_args
from ssl import create_default_context

import httpx

from httpx_oauth.oauth2 import OAuth2ClientAuthMethod, BaseOAuth2

from httpx_oauth.clients.openid import BASE_SCOPES
from httpx_oauth.clients.openid import OpenID, OpenIDConfigurationError


# configure to use Basalt SSL certificates
ssl_context = create_default_context()
ssl_context.load_default_certs()


class CustomOpenID(OpenID):
    '''
    from: https://github.com/frankie567/httpx-oauth/blob/003d13e833f412bc849ced7ed0890d4a4647ff84/httpx_oauth/clients/openid.py
    '''
    def __init__(
        self,
        client_id: str,
        client_secret: str,
        openid_configuration_endpoint: str,
        name: str = "openid",
        base_scopes: Optional[list[str]] = BASE_SCOPES,
    ):
        """
        Args:
            client_id: The client ID provided by the OAuth2 provider.
            client_secret: The client secret provided by the OAuth2 provider.
            openid_configuration_endpoint: OpenID Connect discovery endpoint URL.
            name: A unique name for the OAuth2 client.
            base_scopes: The base scopes to be used in the authorization URL.

        Raises:
            OpenIDConfigurationError:
                An error occurred while fetching the OpenID configuration.

        Examples:
            ```py
            from httpx_oauth.clients.openid import OpenID

            client = OpenID("CLIENT_ID", "CLIENT_SECRET", "https://example.fief.dev/.well-known/openid-configuration")
            ``
        """
        with httpx.Client(verify=ssl_context) as client:
            try:
                response = client.get(openid_configuration_endpoint)
                response.raise_for_status()
            except httpx.HTTPStatusError as e:
                raise OpenIDConfigurationError(str(e), e.response) from e
            except httpx.HTTPError as e:
                raise OpenIDConfigurationError(str(e)) from e
            self.openid_configuration: dict[str, Any] = response.json()

        token_endpoint = self.openid_configuration["token_endpoint"]
        refresh_token_supported = "refresh_token" in self.openid_configuration.get(
            "grant_types_supported", []
        )
        revocation_endpoint = self.openid_configuration.get("revocation_endpoint")
        token_endpoint_auth_methods_supported = self.openid_configuration.get(
            "token_endpoint_auth_methods_supported", ["client_secret_basic"]
        )
        revocation_endpoint_auth_methods_supported = self.openid_configuration.get(
            "revocation_endpoint_auth_methods_supported", ["client_secret_basic"]
        )

        supported_auth_methods = get_args(OAuth2ClientAuthMethod)
        # check if there is any supported and select the first one
        token_endpoint_auth_methods_supported = [
            method
            for method in token_endpoint_auth_methods_supported
            if method in supported_auth_methods
        ]
        revocation_endpoint_auth_methods_supported = [
            method
            for method in revocation_endpoint_auth_methods_supported
            if method in supported_auth_methods
        ]

        BaseOAuth2.__init__(
            self,
            client_id,
            client_secret,
            self.openid_configuration["authorization_endpoint"],
            token_endpoint,
            token_endpoint if refresh_token_supported else None,
            revocation_endpoint,
            name=name,
            base_scopes=base_scopes,
            token_endpoint_auth_method=token_endpoint_auth_methods_supported[0],
            revocation_endpoint_auth_method=(
                revocation_endpoint_auth_methods_supported[0]
                if revocation_endpoint
                else None
            ),
        )

    def get_httpx_client(self):
        return httpx.AsyncClient(verify=ssl_context)
