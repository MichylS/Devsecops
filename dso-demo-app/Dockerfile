# nginx-unprivileged draait als gebruiker 101 op poort 8080 (geen root nodig)
FROM nginxinc/nginx-unprivileged:alpine
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY index.html style.css /usr/share/nginx/html/
USER 101
