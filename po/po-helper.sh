#!/bin/sh
#
# Copyright (c) 2012 Jiang Xin

POTFILE=git.pot

OPTIONS_SPEC="\
po-helper.sh XX.po
po-helper.sh check [XX.po]
po-helper.sh commits [from] [to]
po-helper.sh pot
--
"
#. ../git-sh-setup

usage()
{
	echo "..."
}

show_pot_update_summary()
{
	pnew="^.*:([0-9]+): this message is used but not defined in"
	pdel="^.*:([0-9]+): warning: this message is not used"
	new_count=0
	del_count=0
	new_lineno=""
	del_lineno=""

	status=$(git status --porcelain -- $POTFILE)
	if [ -z "$status" ]; then
		echo "Nothing changed."
	else
		tmpfile=$(mktemp /tmp/git.po.XXXX)
		LANGUAGE=C git show HEAD:./git.pot > $tmpfile
		LANGUAGE=C msgcmp -N --use-untranslated $tmpfile $POTFILE 2>&1 |
		{	while read line; do
				if [[ $line =~ $pnew ]]; then
					new_count=$(( new_count + 1 ))
					if [ -z "$new_lineno" ]; then
						new_lineno="${BASH_REMATCH[1]}"
					else
						new_lineno="${new_lineno}, ${BASH_REMATCH[1]}"
					fi
				fi
				if [[ $line =~ $pdel ]]; then
					del_count=$(( del_count + 1 ))
					if [ -z "$del_lineno" ]; then
						del_lineno="${BASH_REMATCH[1]}"
					else
						del_lineno="${del_lineno}, ${BASH_REMATCH[1]}"
					fi
				fi
			done
			[ $new_count -gt 1 ] && new_plur="s" || new_plur=""
			[ $del_count -gt 1 ] && del_plur="s" || del_plur=""
			echo "Updates of $POTFILE since last update:"
			echo
			echo " * Add ${new_count} new l10n message${new_plur}" \
				 "in the new generated \"git.pot\" file at" \
				 "line${new_plur}:"
			echo "   ${new_lineno}"
			echo

			echo " * Remove ${del_count} l10n message${del_plur}" \
				 "from the old \"git.pot\" file at line${del_plur}:"
			echo "   ${del_lineno}"
		}
		rm $tmpfile
	fi
}

check_po()
{
	if [ $# -eq 0 ]; then
		ls *.po | while read f; do
			echo "============================================================"
			echo "Check $f..."
			check_po $f
		done
	fi
	while [ $# -gt 0 ]; do
		po=$1
		shift
		if [ -f $po ]; then
			msgfmt -o /dev/null --check --statistics $po
		else
			echo "Error: File $po does not exist."
		fi 
	done
}

create_or_update_po()
{
	if [ $# -eq 0 ]; then
		usage
		exit 1
	fi
	while [ $# -gt 0 ]; do
		po=$1
		shift
		if [ -f $po ]; then
			msgmerge --add-location --backup=off -U $po $POTFILE
		else
			msginit -i $POTFILE --locale=${po%.po}
		fi 
		mo="build/locale/${po%.po}/LC_MESSAGES/git.mo"
		mkdir -p $(dirname $mo)
		msgfmt -o $mo --check --statistics $po
	done
}


verify_commit_encoding()
{
	c=$1
	subject=0
	non_ascii=""
	encoding=""
	log=""

  echo check commit $c
	git cat-file commit $c |
	{
		while read line; do
			log="$log - $(echo ${line} | sed -e 's/[[:punct:]]/ /g')"
			# next line would be the commit log subject line,
			# if no previous empty line found.
			if [ -z "$line" ]; then
				subject=$((subject + 1))
				continue
			fi
      pencoding="^encoding (.+)"
			if [ $subject -eq 0 ] && [[ $line =~ $pencoding ]]; then
				encoding="${BASH_REMATCH[1]}"
			fi
			# non-ascii found in commit log
      pnoascii="([^[:alnum:][:space:][:punct:]]+)"
			if [[ $line =~ $pnoascii ]]; then
				non_ascii="$line << ${BASH_REMATCH[1]}"
				if [ $subject -eq 1 ]; then
					report_nonascii_in_subject $c $non_ascii
					return
				fi
			fi
			# subject has only one line
			[ $subject -eq 1 ] && subject=$((subject += 1))
			# break if there are non-asciis and has already checked subject line
			if [ -n "$non_ascii" ] && [ $subject -gt 0 ]; then
				break
			fi
		done
		if [ -n "$non_ascii" ]; then
			[ -z "$encoding" ] && encoding="UTF-8"
			python -c "s='''$log'''; s.decode('$encoding')" 2>/dev/null ||
			report_bad_encoding $c $non_ascii
		fi
	}
}

report_nonascii_in_subject()
{
	c=$1
	non_ascii=$2

	echo "============================================================"
	echo "Error: Non-ASCII found in subject in commit $c:"
	echo "       ${non_ascii}"
	echo
	git cat-file commit $c | head - 10 | while read line; do
		echo "\t$line"
	done
}

report_bad_encoding()
{
	c=$1
	non_ascii=$2

	echo "============================================================"
	echo "Error: Lost or bad encoding found in commit $c:"
	echo "       ${non_ascii}"
	echo
	git cat-file commit $c | head - 10 | while read line; do
		echo "\t$line"
	done
}

check_commits()
{
	if [ $# -gt 2 ]; then
		usage
		exit 1
	fi
	from=${1:-origin/master}
	to=${2:-HEAD}

	git rev-list ${from}..${to} |
	{	while read c; do
			verify_commit_encoding $c
		done
	}
}


while test $# != 0
do
	case "$1" in
	pot|git.pot)
		show_pot_update_summary
		;;
	*.po)
		create_or_update_po $1
		;;
	check)
		shift
		check_po $*
		exit 0
		;;
	commit|commits)
		shift
		check_commits $*
		exit 0
		;;
	esac
	shift
done
