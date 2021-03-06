%{
/* sieve.l -- sieve lexer
 * Larry Greenfield
 * Ken Murchison
 *
 * Copyright (c) 1994-2017 Carnegie Mellon University.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in
 *    the documentation and/or other materials provided with the
 *    distribution.
 *
 * 3. The name "Carnegie Mellon University" must not be used to
 *    endorse or promote products derived from this software without
 *    prior written permission. For permission or any legal
 *    details, please contact
 *      Carnegie Mellon University
 *      Center for Technology Transfer and Enterprise Creation
 *      4615 Forbes Avenue
 *      Suite 302
 *      Pittsburgh, PA  15213
 *      (412) 268-7393, fax: (412) 268-7395
 *      innovation@andrew.cmu.edu
 *
 * 4. Redistributions of any form whatsoever must retain the following
 *    acknowledgment:
 *    "This product includes software developed by Computing Services
 *     at Carnegie Mellon University (http://www.cmu.edu/computing/)."
 *
 * CARNEGIE MELLON UNIVERSITY DISCLAIMS ALL WARRANTIES WITH REGARD TO
 * THIS SOFTWARE, INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS, IN NO EVENT SHALL CARNEGIE MELLON UNIVERSITY BE LIABLE
 * FOR ANY SPECIAL, INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
 * AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING
 * OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

#ifdef HAVE_CONFIG_H
#include <config.h>
#endif

#include "util.h"

#include "sieve/tree.h"
#include "sieve/sieve_interface.h"
#include "sieve/sieve.h"

#define YY_NO_INPUT
#define YY_DECL int yylex(YYSTYPE *yylval, sieve_script_t *sscript)

static unsigned long long tonum(const char *str);
static struct buf buf;   /* buffer for multi-line text and quoted strings */
extern int getdatepart;  /* used to receive start state feedback from parser */
extern void sieveerror(sieve_script_t *, char *);
extern void sieveerror_f(sieve_script_t *, char *fmt, ...);
%}

%option yylineno
%option noyywrap
%option nounput
%option prefix="sieve" outfile="lex.yy.c"

    /* linebreak */
CRLF            (\r\n|\r|\n)
    
    /* non-linebreaking whitespace */
ws              [ \t]+

    /* UTC offset of timezone +/-hhmm */
timezone        [-|+][0-1][0-9][0-5][0-9]

    /* case-insensitive date-parts */
year            [Y|y][E|e][A|a][R|r]
month           [M|m][O|o][N|n][T|t][H|h]
day             [D|d][A|a][Y|y]
date            [D|d][A|a][T|t][E|e]
julian          [J|j][U|u][L|l][I|i][A|a][N|n]
hour            [H|h][O|o][U|u][R|r]
minute          [M|m][I|i][N|n][U|u][T|t][E|e]
second          [S|s][E|e][C|c][O|o][N|n][D|d]
time            [T|t][I|i][M|m][E|e]
iso8601         [I|i][S|s][O|o]8601
std11           [S|s][T|t][D|d]11
zone            [Z|z][O|o][N|n][E|e]
weekday         [W|w][E|e][E|e][K|k][D|d][A|a][Y|y]

%state MULTILINE
%state QSTRING
%state QCOLLATION
%state QRELATION
%state QIMPORTANCE
%state QTIMEZONE
%state QDATEPART

%%
    /* end of multi-line text */
<MULTILINE>^\.{CRLF}          {
                                  BEGIN INITIAL;
                                  yylval->sval = buf_release(&buf);
                                  return STRING;
                              }

    /* dot stuffing */
<MULTILINE>^\.\.              buf_putc(&buf, yytext[1]);

    /* end of quoted string */
<QSTRING>\"                   {
                                  BEGIN INITIAL;
                                  yylval->sval = buf_release(&buf);
                                  return STRING;
                              }

    /* escaped character */
<QSTRING>\\.                  buf_putc(&buf, yytext[1]);

    /* any character (including LF) */
<QSTRING,MULTILINE>(.|\n)     buf_putc(&buf, yytext[0]);

    /* premature EOF */
<QSTRING,MULTILINE><<EOF>>    {
                                  BEGIN INITIAL;
                                  sieveerror(sscript,
                                             "unexpected end of file in string");
                                  buf_free(&buf);
                                  yyterminate();
                              }

    /* beginning of multi-line text */
<INITIAL>text:{ws}?(#.*)?{CRLF} {
                                  BEGIN MULTILINE;
                                  buf_init(&buf);
                              }

    /* beginning of quoted string */
<INITIAL>\"                   {
                                  if (getdatepart) {
                                      BEGIN QDATEPART;
                                      getdatepart = 0;
                                      yyless(0);
                                  }
                                  else {
                                      BEGIN QSTRING;
                                      buf_init(&buf);
                                  }
                              }

    /* number with optional power of 2 suffix */
<INITIAL>[0-9]+[KMGkmg]?      {
                                  unsigned long long val = tonum(yytext);
                                  if (val > INT_MAX) {
                                      sieveerror_f(sscript,
                                                   "number too large %s",
                                                   yytext);
                                  }
                                  yylval->nval = val;
                                  return NUMBER;
                              }

    /* standard control commands - RFC 5228 */
<INITIAL>if                   return IF;
<INITIAL>elsif                return ELSIF;
<INITIAL>else                 return ELSE;
<INITIAL>require              return REQUIRE;
<INITIAL>stop                 return STOP;

    /* standard tests - RFC 5228 */
<INITIAL>anyof                return ANYOF;
<INITIAL>allof                return ALLOF;
<INITIAL>exists               return EXISTS;
<INITIAL>false                return SFALSE;
<INITIAL>true                 return STRUE;
<INITIAL>not                  return NOT;
<INITIAL>header               return HEADERT;
<INITIAL>address              return ADDRESS;
<INITIAL>envelope             return ENVELOPE;
<INITIAL>size                 return SIZE;
<INITIAL>:over                return yylval->nval = OVER;
<INITIAL>:under               return yylval->nval = UNDER;

    /* standard action commands - RFC 5228 */
<INITIAL>discard              return DISCARD;
<INITIAL>keep                 return KEEP;
<INITIAL>fileinto             return FILEINTO;
<INITIAL>redirect             return REDIRECT;

    /* copy - RFC 3894 */
<INITIAL>:copy                return COPY;

    /* comparator-types - RFC 5228 */
<INITIAL>:comparator          { BEGIN QCOLLATION; return COMPARATOR; }

<QCOLLATION>[ \t\n\r] ;       /* ignore whitespace */
<QCOLLATION>\"i;octet\"       {
                                  BEGIN INITIAL;
                                  return yylval->nval = OCTET;
                              }
<QCOLLATION>\"i;ascii-casemap\" {
                                  BEGIN INITIAL;
                                  return yylval->nval = ASCIICASEMAP;
                              }
<QCOLLATION>\"i;ascii-numeric\" {
                                  BEGIN INITIAL;
                                  return yylval->nval = ASCIINUMERIC;
                              }
<QCOLLATION>\"[^\"]*\"        {
                                  BEGIN INITIAL;
                                  sieveerror_f(sscript,
                                               "unknown comparator-name %s",
                                               yytext);
                              }

    /* match-types - RFC 5228 */
<INITIAL>:is                  return yylval->nval = IS;
<INITIAL>:contains            return yylval->nval = CONTAINS;
<INITIAL>:matches             return yylval->nval = MATCHES;

    /* regex - draft-ietf-sieve-regex */
<INITIAL>:regex               return yylval->nval = REGEX;
<INITIAL>:quoteregex          return yylval->nval = QUOTEREGEX;

    /* extlists - RFC 6134 */
<INITIAL>:list                return yylval->nval = LIST;
<INITIAL>valid_ext_list       return VALIDEXTLIST;

    /* address-parts - RFC 5228 */
<INITIAL>:all                 return yylval->nval = ALL;
<INITIAL>:localpart           return yylval->nval = LOCALPART;
<INITIAL>:domain              return yylval->nval = DOMAIN;

    /* subaddress - RFC 5233 */
<INITIAL>:user                return yylval->nval = USER;
<INITIAL>:detail              return yylval->nval = DETAIL;

    /* body - RFC 5173 */
<INITIAL>body                 return BODY;
<INITIAL>:raw                 return yylval->nval = RAW;
<INITIAL>:text                return yylval->nval = TEXT;
<INITIAL>:content             return yylval->nval = CONTENT;

    /* variables - RFC 5229 */
<INITIAL>string               return STRINGT;
<INITIAL>set                  return SET;
<INITIAL>:lower               return yylval->nval = LOWER;
<INITIAL>:upper	              return yylval->nval = UPPER;
<INITIAL>:lowerfirst          return yylval->nval = LOWERFIRST;
<INITIAL>:upperfirst          return yylval->nval = UPPERFIRST;
<INITIAL>:quotewildcard       return yylval->nval = QUOTEWILDCARD;
<INITIAL>:length              return yylval->nval = LENGTH;

    /* vacation - RFC 5230 */
<INITIAL>vacation             return VACATION;
<INITIAL>:days                return DAYS;
<INITIAL>:addresses           return ADDRESSES;
<INITIAL>:subject             return SUBJECT;
<INITIAL>:from                return FROM;
<INITIAL>:handle              return HANDLE;
<INITIAL>:mime                return MIME;

    /* vacation-seconds - RFC 6131 */
<INITIAL>:seconds             return SECONDS;

    /* relational - RFC 5231 */
<INITIAL>:count               { BEGIN QRELATION; return yylval->nval = COUNT; }
<INITIAL>:value               { BEGIN QRELATION; return yylval->nval = VALUE; }

<QRELATION>[ \t\n\r] ;        /* ignore whitespace */
<QRELATION>\"eq\"             { BEGIN INITIAL; return yylval->nval = EQ; }
<QRELATION>\"ne\"             { BEGIN INITIAL; return yylval->nval = NE; }
<QRELATION>\"gt\"             { BEGIN INITIAL; return yylval->nval = GT; }
<QRELATION>\"ge\"             { BEGIN INITIAL; return yylval->nval = GE; }
<QRELATION>\"lt\"             { BEGIN INITIAL; return yylval->nval = LT; }
<QRELATION>\"le\"             { BEGIN INITIAL; return yylval->nval = LE; }
<QRELATION>\"[^\"]*\"         {
                                  BEGIN INITIAL;
                                  sieveerror_f(sscript,
                                               "invalid relational-match %s",
                                               yytext);
                              }

    /* imap4flags - RFC 5232 */
<INITIAL>setflag              return yylval->nval = SETFLAG;
<INITIAL>addflag              return yylval->nval = ADDFLAG;
<INITIAL>removeflag           return yylval->nval = REMOVEFLAG;
<INITIAL>hasflag              return yylval->nval = HASFLAG;
<INITIAL>:flags               return FLAGS;

    /* imapflags - draft-melnikov-sieve-imapflags-04 */
<INITIAL>mark                 return yylval->nval = MARK;
<INITIAL>unmark               return yylval->nval = UNMARK;

    /* date - RFC 5260 */
<INITIAL>date                 return DATE;
<INITIAL>:originalzone        return ORIGINALZONE;
<INITIAL>:zone                { BEGIN QTIMEZONE; return ZONE; }
<INITIAL>currentdate          { getdatepart = 1; return CURRENTDATE; }

<QTIMEZONE>[ \t\n\r] ;        /* ignore whitespace */
<QTIMEZONE>\"{timezone}\"     {
                                  BEGIN INITIAL;
                                  int tz = atoi(yytext+1); /* skip leading " */
                                  yylval->nval = 60 * (tz / 100) + (tz % 100);
                                  return TIMEZONE;
                              }
<QTIMEZONE>\"[^\"]*\"         {
                                  BEGIN INITIAL;
                                  sieveerror_f(sscript,
                                               "invalid time-zone %s", yytext);
                              }

<QDATEPART>\"{year}\"         { BEGIN INITIAL; return yylval->nval = YEARP;    }
<QDATEPART>\"{month}\"        { BEGIN INITIAL; return yylval->nval = MONTHP;   }
<QDATEPART>\"{day}\"          { BEGIN INITIAL; return yylval->nval = DAYP;     }
<QDATEPART>\"{date}\"         { BEGIN INITIAL; return yylval->nval = DATEP;    }
<QDATEPART>\"{julian}\"       { BEGIN INITIAL; return yylval->nval = JULIAN;   }
<QDATEPART>\"{hour}\"         { BEGIN INITIAL; return yylval->nval = HOURP;    }
<QDATEPART>\"{minute}\"       { BEGIN INITIAL; return yylval->nval = MINUTEP;  }
<QDATEPART>\"{second}\"       { BEGIN INITIAL; return yylval->nval = SECONDP;  }
<QDATEPART>\"{time}\"         { BEGIN INITIAL; return yylval->nval = TIMEP;    }
<QDATEPART>\"{iso8601}\"      { BEGIN INITIAL; return yylval->nval = ISO8601;  }
<QDATEPART>\"{std11}\"        { BEGIN INITIAL; return yylval->nval = STD11;    }
<QDATEPART>\"{zone}\"         { BEGIN INITIAL; return yylval->nval = ZONEP;    }
<QDATEPART>\"{weekday}\"      { BEGIN INITIAL; return yylval->nval = WEEKDAYP; }
<QDATEPART>\"[^\"]*\"         {
                                  BEGIN INITIAL;
                                  sieveerror_f(sscript,
                                               "invalid date-part %s", yytext);
                              }


    /* index - RFC 5260 */
<INITIAL>:index               return INDEX;
<INITIAL>:last                return LAST;

    /* editheader - RFC 5293 */
<INITIAL>addheader            return ADDHEADER;
<INITIAL>deleteheader         return DELETEHEADER;
    /*   :index               defined in 'index' */
    /*   :last                defined in 'index' */

    /* [e]reject - RFC 5429 */
<INITIAL>reject               return yylval->nval = REJCT;
<INITIAL>ereject              return yylval->nval = EREJECT;

    /* enotify - RFC 5435 */
<INITIAL>notify               return NOTIFY;
<INITIAL>:method              return METHOD;
<INITIAL>:options             return OPTIONS;
<INITIAL>:message             return MESSAGE;
<INITIAL>:encodeurl           return yylval->nval = ENCODEURL;
<INITIAL>:importance          { BEGIN QIMPORTANCE; return IMPORTANCE; }

<QIMPORTANCE>[ \t\n\r] ;      /* ignore whitespace */
<QIMPORTANCE>\"1\"            { BEGIN INITIAL; return yylval->nval = HIGH;   }
<QIMPORTANCE>\"2\"            { BEGIN INITIAL; return yylval->nval = NORMAL; }
<QIMPORTANCE>\"3\"            { BEGIN INITIAL; return yylval->nval = LOW;    }
<QIMPORTANCE>\"[^\"]*\"       {
                                  BEGIN INITIAL;
                                  sieveerror_f(sscript,
                                               "invalid importance %s", yytext);
                              }

    /* notify - draft-martin-sieve-notify-01 */
<INITIAL>denotify             return DENOTIFY;
<INITIAL>:id                  return ID;
<INITIAL>:low                 return yylval->nval = LOW;
<INITIAL>:normal              return yylval->nval = NORMAL;
<INITIAL>:high                return yylval->nval = HIGH;

    /* ihave - RFC 5463 */
<INITIAL>ihave                return IHAVE;
<INITIAL>error                return ERROR;

    /* mailbox - RFC 5490 */
<INITIAL>mailboxexists        return MAILBOXEXISTS;
<INITIAL>:create              return CREATE;

    /* mboxmetadata - RFC 5490 */
<INITIAL>metadata             return yylval->nval = METADATA;
<INITIAL>metadataexists       return METADATAEXISTS;

    /* servermetadata - RFC 5490 */
<INITIAL>servermetadata       return yylval->nval = SERVERMETADATA;
<INITIAL>servermetadataexists return SERVERMETADATAEXISTS;

    /* include - RFC 6609 */
<INITIAL>include              return INCLUDE;
<INITIAL>:personal            return yylval->nval = PERSONAL;
<INITIAL>:global              return yylval->nval = GLOBAL;
<INITIAL>:optional            return OPTIONAL;
<INITIAL>:once                return ONCE;
<INITIAL>return               return RETURN;

    /* duplicate - RFC 7352 */
<INITIAL>duplicate            return DUPLICATE;
<INITIAL>:header              return yylval->nval = HEADER;
<INITIAL>:uniqueid            return yylval->nval = UNIQUEID;
    /*   :handle              defined in 'vacation' */
    /*   :seconds             defined in 'vacation-seconds' */
    /*   :last                defined in 'index' */

    /* draft-murchison-sieve-fcc */
<INITIAL>:fcc                  return FCC;

<INITIAL>"/*"([^\*]|\*[^\/])*\*?"*/" ;  /* ignore bracketed comments */
<INITIAL>#.* ;                /* ignore hash comments */
<INITIAL>[ \t\n\r] ;          /* ignore whitespace */
.                             return yytext[0];

%%

/* convert numerical string w/units to int */
static unsigned long long tonum(const char *str)
{
    char *units;
    unsigned long long val = strtoull(str, &units, 10);

    if (*units && errno != ERANGE) {
        switch (toupper(*units)) {
        case 'K': val *= (1ULL << 10); break;
        case 'M': val *= (1ULL << 20); break;
        case 'G': val *= (1ULL << 30); break;
            /* for future use */
        case 'T': val *= (1ULL << 40); break;
        case 'P': val *= (1ULL << 50); break;
        case 'E': val *= (1ULL << 60); break;
        default: break;
        }
    }

    return val;
}
