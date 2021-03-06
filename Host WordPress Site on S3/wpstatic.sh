#!/bin/bash

#------------------------------------------------------------------------------#
#   wpstatic: Make a static copy of your WordPress site                        #
#                                                                              #
#   Simply run this script in the folder where you keep the wp-config.php file #
#                                                                              #
#   @Author: Ammon Shepherd                                                    #
#   @Date:   03.24.11                                                          #
   VERSION="1.2.1"
#------------------------------------------------------------------------------#

set -e # End the script if any statement returns a non-true return value
set -u # End script if an unset variable is encountered.

USAGE='
Usage: wpstatic [options]
Version '$VERSION'

Run the script in the directory where you keep the wp-config.php file.
This will create a directory with a static version of the WordPress site,
complete with HTML, CSS, Javascript and images or other media files.

-a Skip everything (database backups, and htaccess check), just generate the static files

-b Skip the first backup of database

-d Skip the second backup of database

-h Show help text

-p Skip changing the permalink and closing comments options in the database

-t Skip check for and changing the .htaccess file

-z Make a zip file of the wp-content, .htaccess, and database files.
'


# Get the options
while getopts "abdhptz" options; do
    case $options in
        a ) SKIPALL="true";;
        b ) SKIPDB1="true";;
        d ) SKIPDB2="true";;
        h ) echo "$USAGE"
            exit 0;;
        p ) SKIPFIX="true";;
        t ) SKIPHT="true";;
        z ) SKIPZIP="true";;
        \? ) echo "$USAGE"
             exit 1;;
        * ) echo "$USAGE"
             exit 1;;
    esac
done
shift `expr $OPTIND - 1`


if [[ ! -f wp-config.php ]]; then
    echo "No wp-config.php"
    exit 3
fi


epsecs=( $(date +'%s') )
path=( $(pwd) )

# Get information from the wp-config.php file in order to make a backup copy
#sqluser=( $(grep "DB_USER" wp-config.php | sed -r -e "s/^[^']+'.*', '([^']+)'.*/\1/") )
#sqlpass=( $(grep "DB_PASSWORD" wp-config.php | sed -r -e "s/^[^']+'.*', '([^']+)'.*/\1/") )
#db_name=`grep "DB_NAME" wp-config.php | sed -r -e "s/^[^']+'.*', '([^']+)'.*/\1/"`
#db_host=`grep "DB_HOST" wp-config.php | sed -r -e "s/^[^']+'.*', '([^']+)'.*/\1/"`
sqluser=( $(grep "DB_USER" wp-config.php | cut -d";" -f1 | cut -d"=" -f2 | sed -e "s|'||g" -e 's|"||g' -e "s|;||g" -e "s| ||g" -e "s|)||g" -e "s|define(DB_USER,||g") )
sqlpass=( $(grep "DB_PASSWORD" wp-config.php | cut -d";" -f1 | cut -d"=" -f2 | sed -e "s|'||g" -e 's|"||g' -e "s|;||g" -e "s| ||g" -e "s|)||g" -e "s|define(DB_PASSWORD,||g") )
db_name=( $(grep "DB_NAME" wp-config.php | cut -d";" -f1 | cut -d"=" -f2 | sed -e "s|'||g" -e 's|"||g' -e "s|;||g" -e "s| ||g" -e "s|)||g" -e "s|define(DB_NAME,||g") )
db_host=( $(grep "DB_HOST" wp-config.php | cut -d";" -f1 | cut -d"=" -f2 | sed -e "s|'||g" -e 's|"||g' -e "s|;||g" -e "s| ||g" -e "s|)||g" -e "s|define(DB_HOST,||g") )
tb_prefix=( $(grep "table_prefix" wp-config.php | cut -d";" -f1 | cut -d"=" -f2 | sed -e "s|'||g" -e 's|"||g' -e "s|;||g" -e "s| ||g") )


site_url=( $(mysql -u$sqluser -p$sqlpass -h$db_host $db_name --raw --silent --silent --execute="SELECT option_value FROM ${tb_prefix}options WHERE option_name = 'siteurl' LIMIT 1;") )
if [ "$?" -ne 0 ]; then
    echo "Error getting site_url from database. Check the wp-config.php file."
    exit
fi
#Get rid of the trailing slash if there, then add one. This makes sure there is always a trailing slash.
site_url="${site_url%/}/"
path=( $(echo $site_url | cut -d'/' -f4- ) )
if [[ -z "${path-}" ]]; then
    path=""
fi
static=( $(echo $site_url | awk -F/ '{DZ=NF-1}; END {print $DZ}' ) )
cdirs=( $(echo $site_url | cut -d'/' -f4- | awk -F/ '{print NF-1}' ) )

# home url needed for the actual URL of the wp install, could be different from the physical location
home_url=( $(mysql -u$sqluser -p$sqlpass -h$db_host $db_name --raw --silent --silent --execute="SELECT option_value FROM ${tb_prefix}options WHERE option_name = 'home' LIMIT 1;") )

# If the home url is empty, set it to the site_url
if [[ -z "${homeurl-}" ]]; then
    home_url=$site_url
fi

home_url="${home_url%/}/"
home_path=( $(echo $home_url | cut -d'/' -f4- ) )
home_static=( $(echo $home_url | awk -F/ '{DZ=NF-1}; END {print $DZ}' ) )
home_cdirs=( $(echo $home_url | cut -d'/' -f4- | awk -F/ '{print NF-1}' ) )
if [[ 0 > $home_cdirs ]]; then
    home_cdirs="0"
fi


# Check for skipping all backups and changes
if [[ -z "${SKIPALL-}" ]]; then

    table_list=( $(mysql -u$sqluser -p$sqlpass -h$db_host $db_name --raw --silent --silent --execute="SHOW TABLES;") )
    if [ "$?" -ne 0 ]; then
        echo "Error getting list of tables from database. Check results of site_url variable."
        exit
    fi

    # Clear the tables value
    tables="" 
    for tablename in ${table_list[@]}
    do
        if [[ "$tablename" =~ $tb_prefix ]]; then
            tables+="$tablename "
        fi
    done




    ######################################################################
    #####       Create backup of unmolested database
    if [[ -z "${SKIPDB1-}" ]]; then
        echo "Creating backup of MySQL database '$db_name' ..."
        mysqldump -u $sqluser -p$sqlpass -h$db_host $db_name $tables > .${db_name}_${tb_prefix}BACKUP-${epsecs}.sql
        if [ "$?" -ne 0 ]; then
            echo "Error making backup of database. Check value of database and user info variables."
            exit
        fi
    fi




    ######################################################################
    #####       Update the permalink structure and close comments
    if [[ -z "${SKIPFIX-}" ]]; then
        echo
        echo "Updating permalink structure and public db fields. Closing comments and pings on all posts and pages."

        mysql -u $sqluser -p$sqlpass -h$db_host $db_name --execute="UPDATE ${tb_prefix}options SET option_value = '/%year%/%monthnum%/%day%/%postname%/' WHERE ${tb_prefix}options.option_name = 'permalink_structure' LIMIT 1; UPDATE ${tb_prefix}options SET option_value = 1 WHERE ${tb_prefix}options.option_name = 'blog_public' LIMIT 1; UPDATE ${tb_prefix}posts SET comment_status = 'closed'; UPDATE ${tb_prefix}posts SET ping_status = 'closed';"
        if [ "$?" -ne 0 ]; then
            echo "Error running update commands on database. Check value of database and user info variables."
            exit
        fi
    fi



    ######################################################################
    #####       Check and edit .htaccess file
    if [[ -z "${SKIPHT-}" ]]; then
        echo
        echo "Checking .htaccess file"
        if [[ -f .htaccess ]]; then
            if [[ $(grep "RewriteBase /$path" .htaccess) ]]; then
                echo "Current .htaccess seems OK."
                cat .htaccess
                echo
            else
                echo "Added to existing .htaccess file."
                echo '
<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteBase /'$path'
    RewriteCond %{REQUEST_FILENAME} !-f
    RewriteCond %{REQUEST_FILENAME} !-d
    RewriteRule . /'$path'index.php [L]
</IfModule>
                ' >> .htaccess
                cat .htaccess
                echo
            fi
        else
            echo "Created new .htaccess file."
            echo '
<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteBase /'$path'
    RewriteCond %{REQUEST_FILENAME} !-f
    RewriteCond %{REQUEST_FILENAME} !-d
    RewriteRule . /'$path'index.php [L]
</IfModule>
            ' > .htaccess
            cat .htaccess
            echo
        fi
    fi



    ######################################################################
    ######      Backup of updated Database
    if [[ -z "${SKIPDB2-}" ]]; then
        echo "Making new backup of database."
        mysqldump -u $sqluser -p$sqlpass -h$db_host $db_name $tables > .${db_name}_${tb_prefix}BACKUP2-${epsecs}.sql
        if [ "$?" -ne 0 ]; then
            echo "Error making second backup copy. Check value of database and user info variables."
            exit
        fi
    fi

fi # end of skip all check

echo "Don't forget to change the theme files to limit comment, RSS, meta, and login links, and search fields."

wget --mirror --cut-dirs=$home_cdirs -P $home_static-static -nH -np -p -k -E $home_url
echo


if [[ -z "${SKIPALL-}" ]]; then
    ######################################################################
    ######      Make a zip file of the wp-contents and dabase backups
    if [[ -z "${SKIPZIP-}" ]]; then
        echo "Making archive of wp-content, .htaccess, and database backups."
        zip -r wp-content.zip wp-content .${db_name}_${tb_prefix}BACKUP-${epsecs}.sql .${db_name}_${tb_prefix}BACKUP2-${epsecs}.sql .htaccess
        mv wp-content.zip ${home_static}-static
    fi

fi # end of skip all check


exit 0
