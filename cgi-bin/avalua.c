// codi del programa "avalua.cgi" que cal posar a public_html/cgi-bin/
//
// aquest programa llegeix un programa escrit en C, el compila, i l'executa
// contra uns quants jocs de prova

// la feina bruta de la compilació en un entorn segur queda delegada a l'script
// avalua.sh

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdarg.h>
#include <string.h>
#include <time.h>
#include <stdint.h>
#include <openssl/md5.h>
#include <unistd.h>
#include <errno.h>

// from boutell.com
#include "cgic.h"

#define PREFIX "/home/grafs/prefix"
#define BASEPATH PREFIX
#define BN BASEPATH "/problemes"

#define PATH_TO_LIB BASEPATH "/lib"
#define PATH_TO_INC PATH_TO_LIB
#define CC "gcc-4.3 "
#define CFLAGS "-std=c99 -g -pedantic-errors -Wall -Wextra -Werror -Wno-unused -static "
#define CC_LINE CC CFLAGS "-I " PATH_TO_INC " " PATH_TO_LIB "/utils.o "


#define MIN_NIA 1
#define MAX_NIA 1000000
#define MIN_PROBLEM 1
#define MAX_PROBLEM 7


static char *lock_file_path = PREFIX "/lock/graphs_avalua_lock_file";

static char *log_directory = PREFIX "/log/";
static char *results_directory = PREFIX "/results/";

static FILE *logfile = NULL;
static FILE *resfile = NULL;

//static char *dlog_fname = "/tmp/graph_evals/debug.log";
static FILE *dlog = NULL;



#define MAX_FIELD_SIZE 0x100
#define MAX_CODE_SIZE 50037

typedef struct {
	// context
	time_t epoch_time;
	char time_string    [MAX_FIELD_SIZE];
	char ip4            [MAX_FIELD_SIZE];
	char user_agent     [MAX_FIELD_SIZE];
	char referrer_url   [MAX_FIELD_SIZE];
	unsigned char context_md5[0x10];
	unsigned char context_md5s[33];

	// data
	int submitted_nia;
	int submitted_problem;
	char submitted_code [MAX_CODE_SIZE];
	unsigned char data_md5[0x10];
	unsigned char data_md5s[33];

	// results
	bool submission_success;
	bool compilation_success;
	bool execution_success;

	// implementation details
	char fname_log    [MAX_FIELD_SIZE];
	char fname_result [MAX_FIELD_SIZE];
	char fname_code   [MAX_FIELD_SIZE];
	char fname_exec   [MAX_FIELD_SIZE];
	char fname_ccerr  [MAX_FIELD_SIZE];
	char fname_out    [MAX_FIELD_SIZE];
} submission;

static void md5_string(unsigned char *to, unsigned char *from)
{
	//char d[16];
	//for (int i = 0; i < 10; i++) d[i] = '0' + i;
	//for (int i = 0; i < 6;  i++) d[i] = 'a' + i;
	for (int i = 0; i < 16; i++)
	{
		//to[2*i] = d[from[i]/16];
		//to[2*i+1] = d[from[i]%16];
		snprintf((char *)(to+2*i), 3, "%02x", from[i]);
	}
	to[32] = '\0';
}

static void close_with_cgi_error(const char *, ...)
			__attribute__ ((format(printf,1,2)));

// the only function on this program that depends on the CGIC library
// (besides usage of "cgiOut")
static void do_pick_submission(submission *e)
{
	e->submission_success = false;
	e->compilation_success = false;
	e->execution_success = false;

	e->epoch_time = time(NULL);
	struct tm tt; localtime_r(&e->epoch_time, &tt);
	snprintf(e->time_string, MAX_FIELD_SIZE,
				"%04d_%02d_%02d_%02d_%02d_%02d",
				1900+tt.tm_year, 1+tt.tm_mon, tt.tm_mday,
				tt.tm_hour, tt.tm_min, tt.tm_sec);
	strncpy(e->ip4, cgiRemoteAddr, MAX_FIELD_SIZE);
	strncpy(e->user_agent, cgiUserAgent, MAX_FIELD_SIZE);
	strncpy(e->referrer_url , cgiReferrer, MAX_FIELD_SIZE);

	cgiFormResultType r;

        r = cgiFormIntegerBounded("nia",
			&e->submitted_nia, MIN_NIA, MAX_NIA, -1);
	if (r != cgiFormSuccess) {fprintf(cgiOut,"<p>BAD NIA</p>");return;}

	r = cgiFormIntegerBounded("problema",
			&e->submitted_problem, MIN_PROBLEM, MAX_PROBLEM, -1);
	if (r!=cgiFormSuccess){fprintf(cgiOut,"<p>BAD PROBLEM</p>");return;}

	//if (e->submitted_problem == 6) {
	//	fprintf(cgiOut, "<p><b>La correcció d'aquest problema (Algorisme de Prim) encara no està llesta</b></p>");
	//	return;
	//}


	r = cgiFormString("codi", e->submitted_code, MAX_CODE_SIZE);
	if(r!=cgiFormSuccess&&r!=cgiFormEmpty){fprintf(cgiOut,"<p>BAD CODE (%d)</p>",r);return;}

	e->submission_success = true;

	size_t codelen = strlen(e->submitted_code);
	assert(codelen < MAX_CODE_SIZE);
	MD5((unsigned char *)e->submitted_code, codelen, e->data_md5);
	md5_string(e->data_md5s, e->data_md5);
}


/*
static void print_md5(FILE *f, unsigned char *m)
{
	//for (int i = 0; i < 0x10; i++)
	//	fprintf(f, " %02x", m[i]);
	uint64_t *mm = (void *)m;
	fprintf(f, "%016llx_%016llx", mm[0], mm[1]);
}
*/

// secret logging of the whole submission
// TODO: make sure that the submitted program can not see/change the logs
static void do_submission_log(submission *e)
{
	assert(e->submission_success);
	snprintf(e->fname_log, MAX_FIELD_SIZE, "%s%d_%s_%s.log", log_directory,
			e->submitted_nia, e->time_string, e->ip4);
	logfile = fopen(e->fname_log, "w");
	if (!logfile) close_with_cgi_error("CAN NOT CREATE LOGFILE");
	fprintf(logfile, "epoch: %ju\n", (uintmax_t)e->epoch_time);
	fprintf(logfile, "time: %s\n", e->time_string);
	fprintf(logfile, "ip4: %s\n", e->ip4);
	fprintf(logfile, "ua: %s\n", e->user_agent);
	fprintf(logfile, "referrer: %s\n\n", e->referrer_url);

	fprintf(logfile, "nia: %d\n", e->submitted_nia);
	fprintf(logfile, "problem: %d\n", e->submitted_problem);
	fprintf(logfile, "code_md5: %s\n", e->data_md5s);
	fprintf(logfile, "code:\n%s", e->submitted_code);
	fclose(logfile);
	logfile = NULL;
}

static void do_submission_display(submission *e)
{
	assert(e->submission_success);

	// TODO: use a table here
	fprintf(cgiOut, "<h2>Context</h2>\n");
//	fprintf(cgiOut, "<p><b>Epoch</b>: %ju</p>\n", (uintmax_t)e->epoch_time);
	fprintf(cgiOut, "<p><b>Time</b>: %s</p>\n", e->time_string);
	fprintf(cgiOut, "<p><b>IP</b>: %s</p>\n", e->ip4);
	fprintf(cgiOut, "<p><b>User Agent</b>: %s</p>\n", e->user_agent);
//	fprintf(cgiOut, "<p><b>Referrer URL</b>: %s</p>\n",e->referrer_url);
//	fprintf(cgiOut, "<p><b>Context md5</b>: %d</p>\n", 0);
//	fprintf(cgiOut, "<p><b>Logfile</b>: %s</p>\n", e->fname_log);
	fprintf(cgiOut, "<p><b>CC</b>: %s</p>\n", CC CFLAGS);

	fprintf(cgiOut, "<h2>Dades</h2>\n");
        fprintf(cgiOut, "<p><b>NIA</b>: %d</p>\n", e->submitted_nia);
	fprintf(cgiOut, "<p><b>Problema</b>: %d</p>\n", e->submitted_problem);
        fprintf(cgiOut, "<p><b>Codi</b>:</p>\n\n<blockquote><pre>\n");
	char tt[]={0,'\0'}, *t, *s = e->submitted_code;
	int c; while ((c = *s++) != 0) {
		switch(c) {
		case '<':  t = "&lt;"; break;
		case '>':  t = "&gt;"; break;
		case '\"': t = "&quot;"; break;
		case '&':  t = "&amp;"; break;
		default:  tt[0] = c; t = tt; break;
		}
		fputs(t, cgiOut);
	}
	fprintf(cgiOut,	"</pre></blockquote>\n");
	fprintf(cgiOut, "<p><b>MD5</b>: %s</p>\n", e->data_md5s);
	//print_md5(cgiOut, e->data_md5);
	//fprintf(cgiOut, "</p>\n");
}

// TODO: fer això de manera segura i raonable
#define HACK_CODE PREFIX "/tmp/programa.c"
#define HACK_EXEC PREFIX "/tmp/programa.c.out"
#define HACK_ERR  PREFIX "/tmp/programa.c.error"

// execute, log, and display compilation
static void do_compile(submission *e)
{
	char *tmp_cname = HACK_CODE; // TODO: to be changed each run!
	FILE *f = fopen(tmp_cname, "w");
	if (!f) close_with_cgi_error("CAN NOT CREATE CODE FILE");
	fprintf(f, "%s", e->submitted_code);
	fclose(f);
	//fprintf(cgiOut, "<tt><b>" CC_LINE HACK_CODE " -o " HACK_EXEC " 2>" HACK_ERR "</b></tt>\n");
	int rsys;
	rsys = system(CC_LINE " " HACK_CODE " -o " HACK_EXEC " 2>" HACK_ERR);

	e->compilation_success = (rsys == 0);
}

static FILE *results_file(submission *e)
{
	snprintf(e->fname_result, MAX_FIELD_SIZE, "%s/%d.%s",
			results_directory, e->submitted_nia, e->data_md5s);
	FILE *r = fopen(e->fname_result, "w");
	if (!r)
		close_with_cgi_error("CAN NOT CREATE RESULTS FILE \"%s\" (%s)",
				e->fname_result,
				strerror(errno));
	fprintf(r, "nia: %d\n", e->submitted_nia);
	fprintf(r, "problema: %d\n", e->submitted_problem);
	fprintf(r, "md5: %s\n", e->data_md5s);
	fprintf(r, "ip: %s\n", e->ip4);
	fprintf(r, "ua: %s\n", e->user_agent);
	fprintf(r, "\n\n\n");
	return r;
}

// execute, log, and display execution
// CALL THE SHELL SCRIPT "avalua.sh" WITHIN A CHROOTED ENVIRONMENT
static void do_check(submission *e)
{
	int nbuf = 0x2000; char buf[nbuf];
	snprintf(buf, nbuf, "cd " BN " && ./avalua.sh %d %s\n",
			e->submitted_problem, HACK_EXEC);
	//fprintf(cgiOut, "evaluation: \"%s\"\n", buf);

	//return;
	//FILE *f = popen(BN "avalua_single.sh " BN "1 pub_2 " HACK_EXEC, "r");
	FILE *f = popen(buf, "r");
	//fprintf(cgiOut, "<p><b>Evaluation script execution</b>: %s</p>\n",
	//		f?"SUCCESSFUL":"ERROR IN SCRIPT!");
	if (f) {
		FILE *rf = results_file(e);
		//fprintf(cgiOut, "<p><b>Script digest</b>:</p>\n");
		fprintf(cgiOut,	"<blockquote><pre style=\"color:blue\">\n");
		int c;
		while((c = fgetc(f)) != EOF) {
			fputc(c, cgiOut);
			fputc(c, rf);
		}
		fprintf(cgiOut, "</pre></blockquote>\n");
		pclose(f);
		fclose(rf);
	} else {
		close_with_cgi_error("CAN NOT RUN EVALUATION SCRIPT (%s)\n",
				strerror(errno));
	}
	fprintf(cgiOut, "<p>Si hi ha algun resultat INCORRECTE, però el vostre programa s'executa correctament, pot ser degut a algun error de format.  Llegiu atentament l'<a href=\"../problems/%d/desc.txt\">explicació</a> del format de sortida i comproveu que està bé.</p>\n",
			e->submitted_problem);

	fprintf(cgiOut, "<p>Si hi ha algun reultat INCORRECTE i el vostre programa retorna un <i>exit status</i> diferent de zero, podeu identificar en quin punt ha fallat llegint el codi del programa i buscant en quin moment es retorna aquest valor</p>\n");

	fprintf(cgiOut, "<p>Si hi ha algun resultat INCORRECTE, seguit per un DIAGNÒSTIC amb números estranys, això pot voler dir vàries coses.  Si diu que el programa ha estat \"killed\" o \"stopped\", és que heu fet segmentation fault, o heu sobrepassat el límit de temps de CPU permès.  Si diu que hi ha \"too much XXX-calls\", és que esteu fent servir funcions no autoritzades.\n</p>\n");

	fprintf(cgiOut, "<p>Si trobeu algun altre tipus de comportament, segurament haureu descober un bug en l'script d'avaluació.  Us agrairíem que ens ho comuniquéssiu tant aviat com sigui possible.\n</p>\n");
}

static bool create_lock_file(void)
{
	int r = symlink(PREFIX "/lock/fitxer_que_existeix_sempre",
			lock_file_path);
	if (r) {
		fprintf(dlog, "can not create lock (%s)\n", strerror(errno));
	}
	return (r != 0);
}

static void remove_lock_file(void)
{
	int r = unlink(lock_file_path);
}

static void bye(void)
{
	if (logfile)
		fclose(logfile);
	if (dlog)
	{
		fprintf(dlog, "closing shit\n");
		fclose(dlog);
	}
	remove_lock_file();
}

static void close_html(void)
{
	fprintf(cgiOut, "\n\n<hr />fi\n</body>\n</html>\n");
}

static void close_with_cgi_error(const char *fmt, ...)
{
	va_list argp;
	va_start(argp, fmt);
	vfprintf(cgiOut, fmt, argp);
	va_end(argp);
	close_html();
	exit(EXIT_SUCCESS);
}



static const char *html_boilerplate =
"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
"<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\"\n"
"\"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">\n"
"<html xmlns=\"http://www.w3.org/1999/xhtml\" lang=\"%s\" xml:lang=\"%s\">\n";


// TODO: use an external stylesheet
static const char *css =
"h1 { color:darkgreen }\n"
"h2 { color:brown }\n"
".win { color:green }\n"
".fail { color:red }\n"
"pre { color:blue; border-style:solid; border-width:1px; border-color:black; padding:20px 20px 20px 20px; }\n";


int cgiMain()
{
	fprintf(stderr, "tralara pipiu\n");
	dlog = fopen(PREFIX "/tmp/fockin_el", "w");
	if (dlog) {
		fprintf(dlog, "good shit\n");
		//fclose(dlog);
	}

	if (atexit(bye)) {fprintf(dlog,"atexit fail\n");return EXIT_FAILURE;}

	submission e[1];

	cgiHeaderContentType("text/html");
	fprintf(cgiOut, html_boilerplate, "ca", "ca");
	fprintf(cgiOut, "<head><title>Avaluació de la pràctica de grafs"
			"</title>\n");
	fprintf(cgiOut, "<style type=\"text/css\"><!--\n"
			"%s\n-->\n</style>\n", css);
	fprintf(cgiOut, "</head>\n<body>\n");
	fprintf(cgiOut, "<h1>Avaluació de la pràctica de grafs</h1>\n");

	if(create_lock_file())
		close_with_cgi_error("CAN NOT CREATE LOCK FILE<br /><br />"
				"(Espereu 15 segons, i torneu-ho a intentar.  "
				"Si el problema persisteix, envieu un mail "
				"als professors de l'assignatura.)");

	do_pick_submission(e);
	if (!e->submission_success)
		close_with_cgi_error("BAD SUBMISSiON");

	do_submission_log(e);
	do_submission_display(e);

	fprintf(cgiOut, "<h2>Avaluació</h2>\n");

	do_compile(e);
	fprintf(cgiOut, "<h3>Compilació del programa</h3>\n");
	if (!e->compilation_success)
	{
		fprintf(cgiOut, "<p><blockquote><b class=\"fail\">ERROR:</b></p><pre style=\"color:red\">");
		FILE *f = fopen(HACK_ERR, "r");
		int c; while((c = fgetc(f)) != EOF)
			fputc(c, cgiOut);
		fclose(f);
		fprintf(cgiOut, "</pre></blockquote>\n");
		goto surt;
	}
	fprintf(cgiOut, "<blockquote><p><b class=\"win\">CORRECTE</b></p></blockquote>");


	fprintf(cgiOut, "<h3>Execució del programa</h3>\n");

	do_check(e);

surt:
	close_html();
	return EXIT_SUCCESS;
}
