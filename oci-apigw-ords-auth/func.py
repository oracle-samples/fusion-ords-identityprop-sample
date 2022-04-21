# Copyright (c)  2022,  Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
import datetime
import io
import json
import logging
from datetime import timedelta
from fdk import response
from requests.auth import HTTPBasicAuth
import requests
import ociVault

oauth_apps = {}

def initContext(context):
    logging.getLogger().debug("initContext called")
    # This method takes elements from the Application Context and from OCI Vault to create the OAuth App Clients object.
    if len(oauth_apps) < 2:
        logging.getLogger().info('Retrieving details about the API and backend OAuth Apps')
        try:
            logging.getLogger().info('initContext: Initializing context')
            #
            oauth_apps['idcs'] = {'introspection_endpoint': context['idcs_introspection_endpoint'],
                                  'client_id': context['idcs_app_client_id'],
                                  'client_secret': ociVault.get_secret(context['idcs_app_client_secret_ocid'])}
            oauth_apps['ords'] = {'token_endpoint': context['back_end_token_endpoint'],
                                  'client_id': context['back_end_app_client_id'],
                                  'client_secret': ociVault.get_secret(context['back_end_client_secret_ocid'])}
            oauth_apps['fusion'] = {"fusion_hostname": f'{context["fusion_hostname"]}'
                                    }

        except Exception as ex:
            logging.getLogger().critical(f'ERROR [initContext]: Failed to get the configs {ex}')
            raise
    else:
        logging.getLogger().info('OAuth Apps already cached')


def introspect_token(access_token, introspection_endpoint, client_id, client_secret):
    #TODO REMOVE
    logging.getLogger().debug(
        f"introspect_token called : endpoint={introspection_endpoint} clientid={client_id} clientsecret{client_secret} token= {access_token}")

    # This method handles the introspection of the received auth token to IDCS.  
    payload = {'token': access_token}
    headers = {'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
               'Accept': 'application/json'}
    try:
        token = requests.post(url=introspection_endpoint,
                              data=payload,
                              headers=headers,
                              auth=HTTPBasicAuth(client_id,
                                                 client_secret))
        if token.status_code != 200:
            # Unauthorised
            logging.getLogger().error(
                f"Unable to introspect Bearer Token provided, got {token.status_code} {token.text}")
            raise Exception("Bearer Token provided Unauthorised error")
    except Exception as ex:
        logging.getLogger().critical("introspectToken: Failed to introspect token" + str(ex))
        raise

    return token.json()


def get_backend_authtoken(token_endpoint, client_id, client_secret):
    # TODO REMOVE
    logging.getLogger().debug(f"get_backend_authtoken called : {token_endpoint} , CI {client_id} CS {client_secret}")
    # This method gets the token from the back-end system (ORDS in this case)
    payload = {'grant_type': 'client_credentials'}
    headers = {'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8'}

    try:
        r = requests.post(token_endpoint,
                          data=payload,
                          headers=headers,
                          auth=HTTPBasicAuth(client_id, client_secret))

        if r.status_code != 200:
            logging.getLogger().error(f"Error {str(r.status_code)} whilst getting backend token")
            raise Exception("Error whilst getting backend token")
        backend_token = r.json()
    except Exception as ex:
        logging.getLogger().critical(f"get_backend_authtoken: Failed to get ORDS token {str(ex)}")
        raise
    logging.getLogger().info('ORDS token acquired')
    return backend_token


def get_fusion_roles(token, username, context):
    # TODO REMOVE
    logging.getLogger().debug(f"get_fusion_roles called :  user = {username}, token={token}")
    returned_roles = ""
    headers = {'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
               'Authorization': f'Bearer {token}'
               }
    logging.getLogger().debug(f'{headers=}')
    fusion_hostname = context['fusion']['fusion_hostname']
    logging.getLogger().debug("fusion hostname " + fusion_hostname)
    get_user_account_endpoint = f'https://{fusion_hostname}/hcmRestApi/resources/11.13.18.05/userAccounts'

    # Use query params to enable escaping of characters
    get_user_account_query_params = {
        'q': f'Username={username}',
        'fields': 'GUID',
        'onlyData': 'true'
    }
    logging.getLogger().debug("get user endpoint=" + get_user_account_endpoint)
    try:
        fusion_response = requests.get(url=get_user_account_endpoint,
                                       params=get_user_account_query_params,
                                       headers=headers
                                       )
        if fusion_response.status_code != 200:
            logging.getLogger().critical(
                f"Error getting user account info from Fusion, got {str(fusion_response.status_code)}")
            raise Exception(
                f"Error getting user account info from Fusion, got {str(fusion_response.status_code)}")
        if len(fusion_response.json()['items']) == 0:
            # User not found, return empty collection
            logging.info(msg="User does not exist in Fusion, returning empty collection")
            return returned_roles

        user_guid = fusion_response.json()['items'][0]['GUID']
        logging.getLogger().critical(f"User Fusion GUID {user_guid}")

        get_user_roles_endpoint = f'https://{fusion_hostname}/hcmRestApi/resources/11.13.18.05/userAccounts/{user_guid}/child/userAccountRoles?onlyData=true&fields=RoleCode'
        logging.getLogger().debug(" get_user_roles_endpoint=" + get_user_roles_endpoint)

        fusion_response = requests.get(get_user_roles_endpoint,
                                       headers=headers
                                       )
        if fusion_response.status_code != 200:
            error_message = f"Error getting roles from Fusion, got {str(fusion_response.status_code)}"
            logging.getLogger().critical(error_message)
            raise Exception(error_message)

        for fusion_role in fusion_response.json()['items']:
            returned_roles = returned_roles + fusion_role['RoleCode'] + ","
        logging.getLogger().info(f"Fusion Roles discovered for user {username}, Roles {returned_roles}")
        # Return and remove last comma
        return returned_roles[0:len(returned_roles) - 1]

    except Exception as ex:
        logging.getLogger().critical(f"get_fusion_roles: Failed to get user details from SaaS {str(ex)}")


def get_auth_context(token, client_apps):
    # This method populates the Auth Context that will be returned to the gateway.
    auth_context = {}
    # Calling IDCS to validate the token and retrieve the client info
    try:
        token_info = introspect_token(token[len('Bearer '):], client_apps['idcs']['introspection_endpoint'],
                                      client_apps['idcs']['client_id'], client_apps['idcs']['client_secret'])
        logging.getLogger().debug("token introspected ")

    except Exception as ex:
        logging.getLogger().error(f"getAuthContext: Failed to introspect token {str(ex)}")
        raise Exception("Failed to Introspect token")

    # If IDCS confirmed the token valid and active, we can proceed to populate the auth context
    if token_info['active']:
        logging.getLogger().debug("IDCS Token Valid")
        auth_context['active'] = True
        auth_context['principal'] = token_info['sub']
        auth_context['scope'] = token_info['scope']
        auth_context['ordsusername'] = token_info['sub']

        # Retrieving the back-end Token
        backend_token = get_backend_authtoken(client_apps['ords']['token_endpoint'], client_apps['ords']['client_id'],
                                              client_apps['ords']['client_secret'])
        # Get roles from Fusion
        fusion_roles = get_fusion_roles(token[len('Bearer '):], token_info['sub'], oauth_apps)
        #
        logging.getLogger().debug("Fusion roles " + fusion_roles)
        # The maximum TTL for this auth is the lesser of the API Client Auth (IDCS) and the Gateway Client Auth (ORDS)
        if (datetime.datetime.fromtimestamp(token_info['exp']) < (
                datetime.datetime.utcnow() + timedelta(seconds=backend_token['expires_in']))):
            auth_context['expiresAt'] = (datetime.datetime.fromtimestamp(token_info['exp'])).replace(
                tzinfo=datetime.timezone.utc).astimezone().replace(microsecond=0).isoformat()
        else:
            auth_context['expiresAt'] = (
                    datetime.datetime.utcnow() + timedelta(seconds=backend_token['expires_in'])).replace(
                tzinfo=datetime.timezone.utc).astimezone().replace(microsecond=0).isoformat()
        # Storing the back_end_token in the context of the auth decision so we can map it to Authorization header using the request/response transformation policy
        auth_context['context'] = {
            'back_end_token': f"Bearer {str(backend_token['access_token'])}",
            'ords_username': token_info['sub'],
            'fusion_roles': fusion_roles
        }

    else:
        # API Client token is not active, so we will go ahead and respond with the wwwAuthenticate header
        auth_context['active'] = False
        auth_context['wwwAuthenticate'] = 'Bearer realm=\"identity.oraclecloud.com\"'
    logging.getLogger().info("auth context generated")
    return auth_context


def handler(ctx, data: io.BytesIO = None):
    logging.getLogger().info('Entered oci-apigw-ords-auth Handler')
    initContext(dict(ctx.Config()))
    headers={"Content-Type": "application/json"}
    auth_context = {}
    try:
        gateway_auth = json.loads(data.getvalue())
        if 'token' not in gateway_auth:
            logging.getLogger().critical(f"Token not found in gateway auth , found {str(gateway_auth)}")
            return response.Response(
                ctx,
                response_data="No Token Found",
                status_code=401,
                headers=headers
            )
        auth_context = get_auth_context(gateway_auth['token'], oauth_apps)

        if auth_context['active']:
            logging.getLogger().info('Authorizer returning 200 with data...')
            return response.Response(
                ctx,
                response_data=json.dumps(auth_context),
                status_code=200,
                headers=headers
            )
        else:
            logging.getLogger().info('Authorizer returning 401...')
            return response.Response(
                ctx,
                response_data=json.dumps(str(auth_context)),
                status_code=401,
                headers=headers
            )

    except Exception as ex:
        logging.getLogger().error(f'Error during processing :{str(ex)} ')
        # Return 401
        return response.Response(
            ctx,
            response_data=json.dumps(str(auth_context)),
            status_code=401,
            headers=headers
        )
