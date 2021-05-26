#!/bin/bash
# A script that notifies a Telegram channel about IEC faults

# Location definition - Or Haner 6 hard coded#
CITY_ID="50"
STREET_ID="19030"
HOUSE_ID="6"
DISTRICT_ID="803"
# END #

# Check if dependencies are installed
if ! [ -x "$(command -v jq)" ]; then
	echo "ERROR: please install jq"
	exit 1
fi
if ! [ -x "$(command -v md5sum)" ]; then
	echo "ERROR: please install md5sum"
	exit 1
fi

# Functions 
help() {
	echo "Usage: iec_fault_notifier.sh <Options>

	Options:
	-h,--help             : help menu
	--bot-token=<BotToken> : REQUIRED, bot token
	--channel-name=<ChannelName> : REQUIRED, bot token"
}

# Loop through arguments and process them
for ARG in "$@"
do
    case $ARG in
        -h|--help)
        HELP_REQUESTED="Ze Germans"
        shift
        ;;
        --bot-token=*)
        BOT_TOKEN="${ARG#*=}"
        shift
        shift
        ;;
        --channel-name=*)
        CHANNEL_NAME="${ARG#*=}"
        shift
        shift
	;;
        *)
        HELP_REQUESTED="Ze Germans"
        shift 
        ;;
    esac
done

# If help was requested, print help menu
if [ "${HELP_REQUESTED}" ]; then
	help
	exit 0
else
	# Make sure bot token was provided
	if [ -z "${BOT_TOKEN}" ] ; then
		echo "ERROR: bot token is required"
		exit 1
	elif [ -z "${CHANNEL_NAME}" ]; then
		echo "ERROR: channel name is required"
		exit 1
	fi
fi

# Gather info about the current status
if [ -n "${CITY_ID}" ] && [ -n "${STREET_ID}" ] && [ -n "${HOUSE_ID}" ] && [ -n "${DISTRICT_ID}" ]; then 
	# Pull the entire event
	echo "INFO: pulling the latest incident from IEC"
	RAW_STATUS=$(curl -s "https://www.iec.co.il/pages/IecServicesHandler.ashx?a=CheckInterruptByAddress&cityID=${CITY_ID}&streetID=${STREET_ID}&homeNum=${HOUSE_ID}&Districtid=${DISTRICT_ID}" | jq .)

	# Check if the pull was successfull
	if [ -n "${RAW_STATUS}" ]; then
		# Save the check sum and use it to compare againts the previous event
		RAW_STATUS_CHECKSUM=$(echo "${RAW_STATUS}"| md5sum)
		INCIDENT_STATUS=$(echo ${RAW_STATUS} | jq -r .IsActiveIncident)

		# Check the incident's status
		if [ "${INCIDENT_STATUS}" != "null" ] && [ "${INCIDENT_STATUS}" == "true" ]; then
			echo "INFO: found an active incident"
			# Check if there is a new incident since the last pull
			if [ ! -f last_incident_checksum ]; then
				echo "INFO: starting for the first time or could not find the last incident checksum file"
				echo "${RAW_STATUS_CHECKSUM}" > last_incident_checksum
			else
				LAST_INCIDENT_CHECKSUM=$(cat last_incident_checksum)
				if [ "${LAST_INCIDENT_CHECKSUM}" == "${RAW_STATUS_CHECKSUM}" ]; then
					echo "INFO: nothing has changed since the last pull, bye :)"
					exit 0
				fi
			fi

			# Extract the relevant info from the event
			CREW_NAME=$(echo ${RAW_STATUS} | jq -r .CrewName)
			CREW_ASSIGNMENT_TIME=$(echo ${RAW_STATUS} | jq -r .LastCrewAssignment)
			INCIDENT_ID=$(echo ${RAW_STATUS} | jq -r .IncidentID)
			INCIDENT_STATUS_CODE=$(echo ${RAW_STATUS} | jq -r .IncidentStatusCode)
			INCIDENT_STARTED=$(echo ${RAW_STATUS} | jq -r .Time_Outage)
			INCIDENT_STATUS_MSG=$(echo ${RAW_STATUS} | jq -r .IncidentStatusName)
			if [ "${#INCIDENT_STATUS_MSG}" > 145 ]; then
				EXTRACTED_TIME_FROM_STATUS_MSG=$(echo ${INCIDENT_STATUS_MSG} | grep -E -o '\d{2}:\d{2}')
				EXTRACTED_DATE_FROM_STATUS_MSG=$(echo ${INCIDENT_STATUS_MSG} | grep -E -o '\d{2}\/\d{2}\/\d{4}')
			fi

			# Construct the msg to send
			CUSTOM_MSG=""
			CUSTOM_MSG+="זוהתה תקלת חשמל בקיבוצינו
			"
			if [ "${INCIDENT_ID}" != "null" ] && [ -n "${INCIDENT_ID}" ]; then
				CUSTOM_MGS+="מספר התקלה הוא ${INCIDENT_ID}
			"
			fi
			if [ "${INCIDENT_STARTED}" != "null" ] && [ -n "${INCIDENT_STARTED}" ]; then
				STARTED_DATE=$(echo ${INCIDENT_STARTED} | cut -d"T" -f1 | awk -v FS=- -v OFS=/ '{print $3,$2,$1}')
				STARTED_TIME=$(echo ${INCIDENT_STARTED} | cut -d"T" -f2)
				CUSTOM_MSG+="התקלה החלה בתאריך ${STARTED_DATE} בשעה ${STARTED_TIME}
			"
			fi
			if [ "${CREW_NAME}" != "null" ] && [ -n "${CREW_NAME}" ] ; then
				CUSTOM_MSG+="התקלה מטופלת על ידי הצוות ${CREW_NAME} החל מ ${CREW_ASSIGNMENT_TIME}
			"
			fi
			if [ -n "${EXTRACTED_TIME_FROM_STATUS_MSG} ] && [ -n "${EXTRACTED_DATE_FROM_STATUS_MSG} ]; then
				CUSTOM_MSG+="צפי סיום התקלה הוא בתאריך ${EXTRACTED_DATE_FROM_STATUS_MSG} בשעה ${EXTRACTED_TIME_FROM_STATUS_MSG}"
			fi

			# Check if the message variable is not empty
			if [ -n "${CUSTOM_MSG}" ]; then
					# Send the message using all the parameters
					echo "INFO: sending the message to ${CHANNEL_NAME} Telegram channel"
					curl -s -o /dev/null -X POST \
						-H 'Content-Type: application/json;charset=utf-8' \
						-d '{"chat_id": "\@'"${CHANNEL_NAME}"'", "text": "'"${CUSTOM_MSG}"'", "disable_notification": true}' \
						https://api.telegram.org/bot"${BOT_TOKEN}"/sendMessage
					# Check if the message was sent successfully and update the checksum file
					if [ "$?" == "0" ]; then
						echo "INFO: updating the last incident checksum file"
						echo "${RAW_STATUS_CHECKSUM}" > last_incident_checksum
					fi
			else
				echo "ERROR: message was not constructed properly"
				exit 1
			fi
		else
			echo "INFO: power is flowing, no active incidents found"
			exit 0
		fi
	fi
else
	echo "ERROR: one of the location configs was not provided"
	exit 1
fi
