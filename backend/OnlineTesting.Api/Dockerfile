
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY OnlineTesting.Api.csproj ./
RUN dotnet restore OnlineTesting.Api.csproj

COPY . .
RUN dotnet publish OnlineTesting.Api.csproj -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app

COPY --from=build /app/publish .
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "OnlineTesting.Api.dll"]
