/*
 * cups-jobs: PrinterManager'ın CUPS iş yardımcısı.
 *
 * "Samsung CLP-300 (PrinterManager)" kuyruğu gelen işleri basmadan bekletir
 * (job-hold-until-default=indefinite). PrinterManager bu araçla bekleyen işi
 * bulur, belgesini alır, işi siler ve belgeyi kendi penceresinde açar.
 * İstekler yerel CUPS soketinden, çalıştıran kullanıcı adına yapılır.
 *
 *   cups-jobs list <kuyruk>              etkin işler, satır başına:
 *                                        no<TAB>durum<TAB>kullanıcı<TAB>biçim<TAB>başlık
 *                                        (durum: pending, held, processing, stopped)
 *   cups-jobs fetch <iş-no> <dosya>      belgeyi dosyaya yazar, biçimini basar
 *   cups-jobs cancel <iş-no>             işi siler
 */

#include <cups/cups.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static const char *state_name(ipp_jstate_t state)
{
    switch (state) {
    case IPP_JSTATE_PENDING:    return "pending";
    case IPP_JSTATE_HELD:       return "held";
    case IPP_JSTATE_PROCESSING: return "processing";
    case IPP_JSTATE_STOPPED:    return "stopped";
    default:                    return "done";
    }
}

static int list_jobs(const char *queue)
{
    cups_job_t *jobs = NULL;
    int count = cupsGetJobs2(CUPS_HTTP_DEFAULT, &jobs, queue, 0, CUPS_WHICHJOBS_ACTIVE);
    if (count < 0) {
        fprintf(stderr, "İşler okunamadı: %s\n", cupsLastErrorString());
        return 1;
    }

    for (int i = 0; i < count; i++) {
        /* Başlıktaki sekme ve satır sonları satır biçimini bozmasın */
        char title[512];
        snprintf(title, sizeof(title), "%s", jobs[i].title ? jobs[i].title : "");
        for (char *p = title; *p; p++) {
            if (*p == '\t' || *p == '\n' || *p == '\r') *p = ' ';
        }
        printf("%d\t%s\t%s\t%s\t%s\n", jobs[i].id, state_name(jobs[i].state),
               jobs[i].user ? jobs[i].user : "",
               jobs[i].format ? jobs[i].format : "", title);
    }

    cupsFreeJobs(count, jobs);
    return 0;
}

static int fetch_job(int job_id, const char *path)
{
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) {
        perror(path);
        return 1;
    }

    char job_uri[256];
    snprintf(job_uri, sizeof(job_uri), "ipp://localhost/jobs/%d", job_id);

    ipp_t *request = ippNewRequest(CUPS_GET_DOCUMENT);
    ippAddString(request, IPP_TAG_OPERATION, IPP_TAG_URI, "job-uri", NULL, job_uri);
    ippAddInteger(request, IPP_TAG_OPERATION, IPP_TAG_INTEGER, "document-number", 1);
    ippAddString(request, IPP_TAG_OPERATION, IPP_TAG_NAME, "requesting-user-name", NULL, cupsUser());

    /* Yanıttaki belge verisi doğrudan fd'ye yazılır */
    ipp_t *response = cupsDoIORequest(CUPS_HTTP_DEFAULT, request, "/", -1, fd);
    close(fd);

    if (!response || ippGetStatusCode(response) > IPP_STATUS_OK_CONFLICTING) {
        fprintf(stderr, "Belge alınamadı: %s\n", cupsLastErrorString());
        ippDelete(response);
        unlink(path);
        return 1;
    }

    ipp_attribute_t *format = ippFindAttribute(response, "document-format", IPP_TAG_MIMETYPE);
    printf("%s\n", format ? ippGetString(format, 0, NULL) : "application/octet-stream");

    ippDelete(response);
    return 0;
}

static int cancel_job(int job_id)
{
    /* cupsCancelJob2 IPP durum kodu döndürür (başarı: IPP_STATUS_OK = 0) */
    if (cupsCancelJob2(CUPS_HTTP_DEFAULT, NULL, job_id, 0) > IPP_STATUS_OK_CONFLICTING) {
        fprintf(stderr, "İş silinemedi: %s\n", cupsLastErrorString());
        return 1;
    }
    return 0;
}

static int usage(const char *program)
{
    fprintf(stderr, "Kullanım: %s list <kuyruk> | fetch <iş-no> <dosya> | cancel <iş-no>\n", program);
    return 2;
}

int main(int argc, char *argv[])
{
    if (argc == 3 && strcmp(argv[1], "list") == 0) {
        return list_jobs(argv[2]);
    }
    if (argc == 4 && strcmp(argv[1], "fetch") == 0 && atoi(argv[2]) > 0) {
        return fetch_job(atoi(argv[2]), argv[3]);
    }
    if (argc == 3 && strcmp(argv[1], "cancel") == 0 && atoi(argv[2]) > 0) {
        return cancel_job(atoi(argv[2]));
    }
    return usage(argv[0]);
}
