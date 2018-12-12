#!/usr/bin/env bash
# ------------------------------------------------------------------------------------------
# This script will create a role in an Apigee organization with proper permissions for
# connecting a Drupal Apigee Edge module to the org.  The Edge user interface cannot be
# used to do this because the permissions needed are more fine grained than it can display.
#
# You must run this script as a user with the orgadmin role.
# ------------------------------------------------------------------------------------------

set -u
set -o pipefail

# ------------------------------------------------------------------------------------------
# Function: err()
# ------------------------------------------------------------------------------------------
# Print all errors to STDERR
# Global Use:
#   None
# Arguments:
#   Message to print to STDERR
# Returns:
#   None
# ------------------------------------------------------------------------------------------
err() {
  echo "$@" >&2
}

# ------------------------------------------------------------------------------------------
# Function: display_help()
# ------------------------------------------------------------------------------------------
# Display help
# Global Use:
#   None
# Arguments:
#   None
# Returns:
#   None
# ------------------------------------------------------------------------------------------
display_help ()
{
  echo "Description:"
  echo "Create a role that can be used for API connections from Apigee Edge Drupal module"
  echo ""
  echo "Usage:"
  echo "  create-drupal-portal-role.sh -o <org> [-u <orgadmin>] [-r <rolename>]"
  echo ""
  echo "Parameters:"
  echo "  -h      Display this help message"
  echo "  -o      The Apigee org to run this script against"
  echo "  -u      An Apigee User account with orgadmin role to use to authenticate"
  echo "  -b      Base URL to use, defaults to public cloud URL 'https://api.enterprise.apigee.com/v1'"
  echo "  -r      The role name to create, defaults to 'drupalportal'"
  echo "  -d      Display debug information"
  echo ""
  echo "Examples:"
  echo "  install -o myorg                    Run script for org myorg"
  echo "  install -u me@example.com -o myorg  Run script as orgadmin me@example.com for org myorg"
  echo " "
}

# ------------------------------------------------------------------------------------------
# Function: get_edge_connection()
# ------------------------------------------------------------------------------------------
# Get Apigee connection settings and validate we can connect to org
# Global Use:
#   IS_DEBUG Set to '1' to show debugging information
# Arguments:
#   EDGE_ORG_NAME The Edge organization name
#   APIGEE_API_BASE_URL The Apigee API base URL
#   EDGE_ORGADMIN_EMAIL (Optional) The user's email used to connect to Apigee API. The
#                       User will be prompted for this value if not passed in
# Returns:
#   The following global vars are set:
#      EDGE_ORGADMIN_PASSWORD
#      EDGE_ORGADMIN_EMAIL if not passed in, this function will prompt user
# ------------------------------------------------------------------------------------------
function get_edge_connection {
  # Pull in params, or empty if not passed in
  EDGE_ORG_NAME=${1:-}
  APIGEE_API_BASE_URL=${2:-}
  EDGE_ORGADMIN_EMAIL=${3:-}

  EDGE_ORGADMIN_PASSWORD=""

  echo "==== Edge Connection Settings ===="

  # Read email if not already set
  if [[ "$EDGE_ORGADMIN_EMAIL" == "" ]]; then
    echo "What orgadmin account should be used to connect to the Apigee org \"$EDGE_ORG_NAME\"?"
    read -p 'Email: ' EDGE_ORGADMIN_EMAIL
  fi

  # Read password
  if [[ "$EDGE_ORGADMIN_PASSWORD" == "" ]]; then
    echo "Enter password for  \"$EDGE_ORGADMIN_EMAIL\""
    prompt="\"${EDGE_ORGADMIN_EMAIL}\" password:"
    while IFS= read -p "$prompt" -r -s -n 1 char
    do
        if [[ $char == $'\0' ]]
        then
            break
        fi
        prompt='*'
        EDGE_ORGADMIN_PASSWORD+="$char"
    done
    echo ""
  fi

  echo ""
  # Do curl call to see if orgadmin user can connect to the org
  CURL_OPTS=(-s -o /dev/null --write-out "%{http_code}" -u "${EDGE_ORGADMIN_EMAIL}:${EDGE_ORGADMIN_PASSWORD}")
  RESPONSE=$(curl "${CURL_OPTS[@]}" $APIGEE_API_BASE_URL/o/$EDGE_ORG_NAME)

  if [ $IS_DEBUG -eq 1 ] ; then
    echo "1> $RESPONSE"
  fi

  # Make sure the password is valid.
  if [[ "$RESPONSE" == 401 ]]; then
    echo
    echo "Username/Password is incorrect."
    exit 1;
  elif [[ "$RESPONSE" == 403 ]]; then
    err "User '${EDGE_ORGADMIN_EMAIL}' is not an orgadmin for organization: '$EDGE_ORG_NAME'"
    exit 1;
  elif [[ "$RESPONSE" == 000 ]]; then
    err "Error running curl command, can your system connect to the URL \"$APIGEE_API_BASE_URL\"?"
    exit 1;
  elif [[ "$RESPONSE" == 302 ]]; then
    err "Calling Endpoint gives a redirect response, is the a valid BASE URL?: $APIGEE_API_BASE_URL/o/$EDGE_ORG_NAME"
    exit 1;
  elif [[ "$RESPONSE" != 200 ]]; then
    err "Org ${EDGE_ORG_NAME} does not exist."
    exit 1;
  fi
}

# ------------------------------------------------------------------------------------------
# Function: create_drupal_portal_role()
# ------------------------------------------------------------------------------------------
# Create the role and permissions in the Apigee organization
# Global Use:
#   IS_DEBUG Set to '1' to show debugging information
# Arguments:
#   EDGE_ORG_NAME The Edge organization name
#   EDGE_ORGADMIN_EMAIL The user's email used to connect to Apigee API, must have orgadmin
#                       role or calls will fail
#   EDGE_ORGADMIN_PASSWORD The password for the user
#   APIGEE_API_BASE_URL The Apigee API base URL
# Returns:
#   None
# ------------------------------------------------------------------------------------------
function create_drupal_portal_role {

  # Pull in params, or empty if not passed in
  EDGE_ORG_NAME=${1:-}
  EDGE_ORGADMIN_EMAIL=${2:-}
  EDGE_ORGADMIN_PASSWORD=${3:-}

  echo "==== Create Role ===="

  # Check to see if role already exists
  CURL_OPTS=(-s -o /dev/null --write-out '%{http_code}' -m 30 -u "${EDGE_ORGADMIN_EMAIL}:${EDGE_ORGADMIN_PASSWORD}")
  RESPONSE=$(curl "${CURL_OPTS[@]}" $APIGEE_API_BASE_URL/o/$EDGE_ORG_NAME/userroles/${PORTAL_API_ROLE})

  if [ $IS_DEBUG -eq 1 ] ; then
    echo "2> $RESPONSE"
  fi

  # If 404 response, the role does not exist, create it
  if [[ "$RESPONSE" == 404 ]]; then
    echo "Creating role '${PORTAL_API_ROLE}' in org '$EDGE_ORG_NAME'"
    # create role
    RESPONSE=$(curl -X POST "${CURL_OPTS[@]}" $APIGEE_API_BASE_URL/o/$EDGE_ORG_NAME/userroles -H "Content-Type:application/json" -d "{\"role\":[\"${PORTAL_API_ROLE}\"]}\"")

    if [ $IS_DEBUG -eq 1 ] ; then
      echo "3> $RESPONSE"
    fi

  elif [[ "$RESPONSE" == 200 ]]; then
    echo "Role '${PORTAL_API_ROLE}' already exists in org '$EDGE_ORG_NAME'"
  elif [[ "$RESPONSE" == 403 ]]; then
    echo "The user ${EDGE_ORGADMIN_EMAIL} does not have orgadmin priviledges in org '$EDGE_ORG_NAME', getting "
    echo "unauthorized response when checking if role exists in system."
    exit 1
  else
    err "Invalid HTTP response code determining if role $PORTAL_API_ROLE exists: $RESPONSE"
    exit 1
  fi

  echo ""
  echo "==== Create Role Permissions ===="
  echo "Setting permissions on role '$PORTAL_API_ROLE'"
  echo ""

  # GET Permissions
  GET_PERMISSION_PATHS=( "/" "/environments/" "/userroles" "/environments/*/stats/*" )

  for PERMISSION_PATH in "${GET_PERMISSION_PATHS[@]}"; do
    RESPONSE=$(curl -X POST "${CURL_OPTS[@]}" ${APIGEE_API_BASE_URL}/o/$EDGE_ORG_NAME/userroles/${PORTAL_API_ROLE}/permissions \
      -H "Content-Type:application/xml" \
      -d "<ResourcePermission path=\"${PERMISSION_PATH}\"> <Permissions> <Permission>get</Permission> </Permissions> </ResourcePermission>")

      echo "${PERMISSION_PATH}: $RESPONSE"
      if [[ $RESPONSE != "201" ]]; then
        err "Error: Permission was not created properly"
        exit 1
      fi
  done

  # GET PUT Permissions
  GET_PUT_PERMISSION_PATHS=( "/apiproducts" "/companies" "/companies/*/apps")

  for PERMISSION_PATH in "${GET_PUT_PERMISSION_PATHS[@]}"; do
    RESPONSE=$(curl -X POST "${CURL_OPTS[@]}" ${APIGEE_API_BASE_URL}/o/$EDGE_ORG_NAME/userroles/${PORTAL_API_ROLE}/permissions \
      -H "Content-Type:application/xml" \
      -d "<ResourcePermission path=\"${PERMISSION_PATH}\"> <Permissions> <Permission>get</Permission><Permission>put</Permission> </Permissions> </ResourcePermission>")

      echo "${PERMISSION_PATH}: $RESPONSE"

      if [[ $RESPONSE != "201" ]]; then
        err "Error: Permission was not created properly"
        exit 1
      fi
  done

  # GET PUT DELETE Permissions
  GET_PUT_DELETE_PERMISSION_PATHS=( "/developers" "/developers/*/apps" "/developers/*/apps/*" "/companies/*"
    "/companies/*/apps/*" "/apimodels" "/apimodels/*" "/keyvaluemaps" "/keyvaluemaps/*" "/environments/*/keyvaluemaps"
    "/environments/*/keyvaluemaps/*")

  for PERMISSION_PATH in "${GET_PUT_DELETE_PERMISSION_PATHS[@]}"; do
    RESPONSE=$(curl -X POST "${CURL_OPTS[@]}" ${APIGEE_API_BASE_URL}/o/$EDGE_ORG_NAME/userroles/${PORTAL_API_ROLE}/permissions \
      -H "Content-Type:application/xml" \
      -d "<ResourcePermission path=\"${PERMISSION_PATH}\"> <Permissions> <Permission>get</Permission><Permission>put</Permission><Permission>delete</Permission> </Permissions> </ResourcePermission>")

      echo "${PERMISSION_PATH}: $RESPONSE"
      if [[ $RESPONSE != "201" ]]; then
        err "Error: Permission was not created properly"
        exit 1
      fi
  done

  # No Permissions
  NO_PERMISSION_PATHS=( "/users")

  for PERMISSION_PATH in "${NO_PERMISSION_PATHS[@]}"; do
    RESPONSE=$(curl -X POST "${CURL_OPTS[@]}" ${APIGEE_API_BASE_URL}/o/$EDGE_ORG_NAME/userroles/${PORTAL_API_ROLE}/permissions \
      -H "Content-Type:application/xml" \
      -d "<ResourcePermission path=\"${PERMISSION_PATH}\"> <Permissions> </Permissions> </ResourcePermission>")

    echo "${PERMISSION_PATH}: $RESPONSE"
    if [[ $RESPONSE != "201" ]]; then
      err "Error: Permission was not created properly"
      exit 1
    fi
  done

}

# ------------------------------------------------------------------------------------------
# Function: init()
# ------------------------------------------------------------------------------------------
# Makes sure all parameters were passed into script, and if not prompts user for info.
# Global Use:
#   None
# Arguments:
#   "$@" To pass in all parameters for parsing
# Returns:
#   The following globals are set by this function if passed in via parameters:
#     EDGE_ORGADMIN_EMAIL
#     EDGE_ORG_NAME
#     PORTAL_API_ROLE
#     APIGEE_API_BASE_URL
#     IS_DEBUG
# ------------------------------------------------------------------------------------------
function init {
  local OPTIND o u d

  EDGE_ORGADMIN_EMAIL=""
  EDGE_ORG_NAME=""
  PORTAL_API_ROLE='drupalportal'
  APIGEE_API_BASE_URL='https://api.enterprise.apigee.com/v1'
  IS_DEBUG=0

  while getopts ":o:u:r:b:dh" opt; do
    case ${opt} in
      h ) # process option h
        display_help
        exit 0
        ;;
      u ) # User
        EDGE_ORGADMIN_EMAIL=$OPTARG
        ;;
      o ) # Org
        EDGE_ORG_NAME=$OPTARG
        ;;
      r ) # Role
        PORTAL_API_ROLE=$OPTARG
        ;;
      b ) # Role
        APIGEE_API_BASE_URL=$OPTARG
        ;;
      d ) # Debug
        IS_DEBUG=1
        ;;
      \? )
        err "Invalid option: -$OPTARG."
        display_help
        exit 1
        ;;
      : )
        err "Invalid option: $OPTARG requires an argument"
        display_help
        exit 1
        ;;
    esac
  done

  # The variable OPTIND holds the number of options parsed by the last call to getopts. It is common practice to call
  # the shift command at the end of your processing loop to remove options that have already been handled from $@.
  shift $((OPTIND -1))

  if [ $IS_DEBUG -eq 1 ] ; then
    echo "EDGE_ORGADMIN_EMAIL: [${EDGE_ORGADMIN_EMAIL}]"
    echo "EDGE_ORG_NAME: [${EDGE_ORG_NAME}]"
    echo "PORTAL_API_ROLE: [${PORTAL_API_ROLE}]"
    echo "APIGEE_API_BASE_URL: [${APIGEE_API_BASE_URL}]"
    echo "IS_DEBUG: [${IS_DEBUG}]"
  fi

  # Make sure org name is passed in
  if [[ "$EDGE_ORG_NAME" == "" ]] ;then
    err "ERROR: no org specificed. "
    display_help
    exit 1
  fi
}


# ------------------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------------------

# Initialize variables from parameters passed in
init "$@"

# Get edge connection values and verify we can connect to org
get_edge_connection $EDGE_ORG_NAME $APIGEE_API_BASE_URL $EDGE_ORGADMIN_EMAIL

# Create the role
create_drupal_portal_role $EDGE_ORG_NAME $EDGE_ORGADMIN_EMAIL $EDGE_ORGADMIN_PASSWORD

echo "Done. You can now assign a user to this role through the Apigee user interface."